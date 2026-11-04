import AllInUI
import Foundation
import OSLog
import Observation
import PokerAI
import PokerCore
import PokerHost
import TableKit
import ThemeKit

enum TablePhase: Equatable {
  case starting
  case waiting
  case yourTurn(LegalActions)
  case handOver
  case sessionOver
}

/// Bridges the cash session (host actor, bots), the human seat and the table scene. Everything the AI does runs on
/// the session actor; this class only enqueues events and reacts to what the scene has finished showing.
@MainActor @Observable
final class TableController {
  let setup: TableSetup
  let scene: TableScene
  private(set) var phase: TablePhase = .starting
  private(set) var handNumber = 0
  private(set) var snapshot = TableSnapshot()
  var raiseTo: Int?
  private(set) var isRaiseMode = false
  var coachVisible = false
  let coach: CoachController
  private(set) var lastOutcome: HandOutcome?
  private(set) var isMenuOpen = false

  @ObservationIgnored private let model: AppModel
  @ObservationIgnored private let human: LocalHumanSeat
  @ObservationIgnored private var requestSeq: Int?
  @ObservationIgnored private(set) var strategiesBySeat: [Int: any StrategyProvider] = [:]
  @ObservationIgnored private(set) var hostEvents: [LoggedEvent] = []
  @ObservationIgnored private var hostTask: Task<Void, Never>?
  @ObservationIgnored private var coachRequestTask: Task<Void, Never>?
  @ObservationIgnored private var demoRangeShown = false
  @ObservationIgnored var onHandFinished: (@MainActor (HandOutcome) -> Void)?
  @ObservationIgnored private var sessionTask: Task<Void, Never>?
  @ObservationIgnored private var eventTask: Task<Void, Never>?
  @ObservationIgnored private var nextHandSignal: AsyncStream<Void>.Continuation?
  @ObservationIgnored private var stopped = false

  private static let log = Logger(subsystem: "app.allin", category: "TableController")

  init(setup: TableSetup, model: AppModel, systemReduceMotion: Bool) {
    self.setup = setup
    self.model = model
    human = LocalHumanSeat(id: setup.heroSeat)
    let hintLevel = CoachHintPolicy.level(for: setup)
    coach = CoachController(heroSeat: setup.heroSeat, hintLevel: hintLevel)
    let timing = AnimationTiming(
      speedFactor: model.launch.fast ? 0.1 : setup.speed.factor,
      reduceMotion: model.effectiveReduceMotion(system: systemReduceMotion))
    let options = TableSceneOptions(
      timing: timing, hud: TableHUD(rawValue: setup.hud.rawValue) ?? .basic,
      fourColorDeck: model.settings.fourColorDeck, driver: .spriteKit, mode: .live)
    scene = TableScene(resolver: model.themeResolver, options: options, soundBank: model.soundBank)
    do {
      let config = try TableConfig(seatCount: setup.seatCount, smallBlind: setup.smallBlind, bigBlind: setup.bigBlind)
      scene.configure(table: config, seats: Self.seatInfos(setup: setup, model: model), heroSeat: setup.heroSeat)
    } catch {
      Self.log.error("invalid table config: \(String(describing: error))")
    }
    scene.onPresented = { [weak self] event, snapshot in self?.handlePresented(event, snapshot) }
    snapshot = scene.presentedSnapshot
    coachVisible = hintLevel != .off
  }

  private static func seatInfos(setup: TableSetup, model: AppModel) -> [TableSeatInfo] {
    (0..<setup.seatCount).map { seat in
      if seat == setup.heroSeat {
        return TableSeatInfo(seat: seat, name: "You", characterID: "you", styleHint: nil, isHero: true)
      }
      let index = seat - 1
      let characterID = setup.opponentIDs.indices.contains(index) ? setup.opponentIDs[index] : nil
      let character = characterID.flatMap { model.character($0) }
      return TableSeatInfo(
        seat: seat, name: character?.name ?? characterID?.capitalized ?? "Seat \(seat)", characterID: characterID,
        styleHint: character?.style, isHero: false)
    }
  }

  // MARK: Session

  func start() {
    guard sessionTask == nil, !stopped else { return }
    let (signals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    nextHandSignal = continuation
    let directory = model.charactersDirectory
    let fast = model.launch.fast
    let setup = setup
    let human = human
    sessionTask = Task { [weak self] in
      do {
        let seed = setup.seed
        let roster = try await Task.detached { try BotRoster.load(directory: directory, patronSeed: seed) }.value
        var seats: [any Seat] = [human]
        var strategies: [Int: any StrategyProvider] = [:]
        for seat in 1..<setup.seatCount {
          let id = setup.opponentIDs.indices.contains(seat - 1) ? setup.opponentIDs[seat - 1] : "oryn"
          guard let bot = roster.first(where: { $0.id == id }) ?? roster.first else { throw TableError.noBots }
          let think: ThinkTime =
            fast ? .instant : ThinkTime(base: .milliseconds(650), jitter: .milliseconds(700), speed: setup.speed)
          strategies[seat] = bot.strategy
          seats.append(
            BotSeat(id: seat, strategy: bot.strategy, seed: SeedMix.mix(setup.seed, UInt64(seat)), thinkTime: think))
        }
        let table = try TableConfig(
          seatCount: setup.seatCount, smallBlind: setup.smallBlind, bigBlind: setup.bigBlind)
        let session = try CashSession(
          config: CashSessionConfig(table: table, buyIn: setup.buyIn, topUp: .rebuyWhenBusted, seed: setup.seed),
          seats: seats)
        let stream = await session.subscribe(viewer: .seat(setup.heroSeat))
        let hostStream = await session.subscribe(viewer: .host)
        self?.strategiesBySeat = strategies
        self?.consume(stream)
        self?.consumeHost(hostStream)
        var played = 0
        var signalIterator = signals.makeAsyncIterator()
        while !Task.isCancelled {
          if played > 0 { guard await signalIterator.next() != nil else { break } }
          guard let outcome = try await session.playNextHand() else {
            self?.finishSession()
            break
          }
          self?.lastOutcome = outcome
          self?.onHandFinished?(outcome)
          played += 1
        }
      } catch {
        Self.log.error("table session failed: \(String(describing: error))")
        self?.finishSession()
      }
    }
  }

  func stop() {
    stopped = true
    nextHandSignal?.finish()
    nextHandSignal = nil
    sessionTask?.cancel()
    eventTask?.cancel()
    hostTask?.cancel()
    coachRequestTask?.cancel()
    coach.reset()
    sessionTask = nil
    eventTask = nil
    hostTask = nil
    human.cancel()
    scene.onPresented = nil
    scene.cancelAnimations()
  }

  private func consume(_ stream: AsyncStream<SessionEvent>) {
    eventTask = Task { [weak self] in
      for await event in stream {
        guard let self, !Task.isCancelled else { return }
        if case .hand(let logged) = event { scene.enqueue(logged) }
      }
    }
  }

  /// The host's view of the current hand, for the coach. Never shown: the tracker is the only consumer.
  private func consumeHost(_ stream: AsyncStream<SessionEvent>) {
    hostTask = Task { [weak self] in
      for await event in stream {
        guard let self, !Task.isCancelled else { return }
        guard case .hand(let logged) = event else { continue }
        if case .handStarted = logged.event { hostEvents = [] }
        hostEvents.append(logged)
      }
    }
  }

  private func finishSession() {
    guard !stopped else { return }
    phase = .sessionOver
  }

  private func handlePresented(_ event: LoggedEvent, _ snap: TableSnapshot) {
    snapshot = snap
    switch event.event {
    case .handStarted:
      handNumber = Int(event.handID.rawValue)
      phase = .waiting
      requestSeq = nil
      isRaiseMode = false
      raiseTo = nil
      coachVisible = coach.hintLevel != .off
      coach.reset()
      coachRequestTask?.cancel()
    case .actionRequested(let legal) where legal.seat == setup.heroSeat:
      requestSeq = event.seq
      raiseTo = BetSizing.defaultRaiseTo(legal: legal, potTotal: snap.potTotal, bigBlind: snap.bigBlind)
      isRaiseMode = false
      phase = .yourTurn(legal)
      if !demoRangeShown, CoachDemoFlags.opensRangeAtFirstDecision(isDemo: model.launch.isDemo),
        coachFocusSeat != nil
      {
        demoRangeShown = true
        showCoachRange()
      }
    case .handEnded:
      requestSeq = nil
      isRaiseMode = false
      phase = .handOver
    default:
      break
    }
  }

  // MARK: Hero actions

  private var legal: LegalActions? {
    if case .yourTurn(let legal) = phase, !isMenuOpen { return legal }
    return nil
  }

  private func submit(_ action: Action) {
    guard case .yourTurn(let legal) = phase, let seq = requestSeq, legal.isLegal(action) else { return }
    requestSeq = nil
    isRaiseMode = false
    phase = .waiting
    coachRequestTask?.cancel()
    coach.hideRange()
    model.soundBank.play(.uiTap)
    human.submit(action, seq: seq)
  }

  func fold() {
    guard legal != nil else { return }
    submit(.fold)
  }

  func checkCall() {
    guard let legal else { return }
    submit(BetSizing.checkCallAction(legal))
  }

  /// R: enter raise mode, or submit when already in it.
  func raise() {
    guard let legal else { return }
    if isRaiseMode {
      confirm()
    } else if raiseTo != nil || legal.canAllIn {
      if raiseTo == nil { raiseTo = legal.allInTo }
      isRaiseMode = true
    }
  }

  /// The "Raise to X" button: submits straight away.
  func submitRaise() {
    guard let legal, let amount = raiseTo, let action = BetSizing.action(raiseTo: amount, legal: legal) else { return }
    submit(action)
  }

  /// Return: submits when in raise mode.
  func confirm() {
    guard isRaiseMode else { return }
    submitRaise()
  }

  func step(_ delta: Int) {
    guard let legal, let current = raiseTo ?? BetSizing.clamp(snapshot.bigBlind, legal: legal) else { return }
    raiseTo = BetSizing.step(current, by: delta, legal: legal, bigBlind: snapshot.bigBlind)
    isRaiseMode = true
  }

  /// Slider value.
  func setRaiseTo(_ amount: Int) {
    guard let legal, let clamped = BetSizing.clamp(amount, legal: legal) else { return }
    raiseTo = clamped
    isRaiseMode = true
  }

  func preset(_ index: Int) {
    guard let legal, let preset = BetPreset(rawValue: index),
      let amount = BetSizing.raiseTo(preset, legal: legal, potTotal: snapshot.potTotal)
    else { return }
    raiseTo = amount
    isRaiseMode = true
  }

  func nextHand() {
    guard phase == .handOver, !isMenuOpen else { return }
    phase = .waiting
    nextHandSignal?.yield()
  }

  func dismissCoach() {
    coachVisible = false
    coach.hideRange()
  }

  // MARK: Coach

  /// The opponent the coach talks about: the biggest committed live opponent this street, else the last opponent to
  /// act voluntarily, else the first live one.
  var coachFocusSeat: Int? {
    let live = snapshot.seats.filter { !$0.info.isHero && ($0.status == .active || $0.status == .allIn) }
    if let bettor = live.filter({ $0.committed > 0 }).max(by: { $0.committed < $1.committed }) {
      return bettor.info.seat
    }
    let liveSeats = Set(live.map(\.info.seat))
    for logged in hostEvents.reversed() {
      if case .actionTaken(let taken) = logged.event, liveSeats.contains(taken.seat) { return taken.seat }
    }
    return live.first?.info.seat
  }

  var coachFocusName: String? {
    coachFocusSeat.flatMap { snapshot.seat($0)?.info.name }
  }

  /// "Q‑T" from the hero's cards, high card first.
  var heroShortName: String {
    guard let cards = snapshot.seat(setup.heroSeat)?.holeCards, cards.count == 2 else { return "your hand" }
    let sorted = cards.sorted { $0.rank > $1.rank }
    return "\(sorted[0].rank.symbol)\u{2011}\(sorted[1].rank.symbol)"
  }

  var canShowCoachRange: Bool {
    if case .yourTurn = phase, !isMenuOpen { return coachFocusSeat != nil }
    return false
  }

  func showCoachRange() {
    guard canShowCoachRange, let seat = coachFocusSeat, let seq = requestSeq,
      let name = snapshot.seat(seat)?.info.name,
      let cards = snapshot.seat(setup.heroSeat)?.holeCards, cards.count == 2
    else { return }
    coach.markLoading(name: name)
    coachRequestTask?.cancel()
    coachRequestTask = Task { [weak self] in
      // The host stream is a separate consumer: give it a moment to catch up with the request we are answering.
      var waited = 0
      while let self, !Task.isCancelled, (self.hostEvents.last?.seq ?? -1) < seq, waited < 100 {
        try? await Task.sleep(for: .milliseconds(20))
        waited += 1
      }
      guard let self, !Task.isCancelled, self.requestSeq == seq else { return }
      let events = self.hostEvents.filter { $0.seq <= seq }
      self.coach.showRange(
        seat: seat, name: name, hostEvents: events, strategies: self.strategiesBySeat, heroCards: cards)
    }
  }

  /// H: open the coach box if it is hidden, otherwise read the focus opponent's range.
  func hint() {
    if !coachVisible, coach.hintLevel != .off {
      coachVisible = true
    } else {
      showCoachRange()
    }
  }

  // MARK: Menu

  func toggleMenu() {
    isMenuOpen.toggle()
  }

  func closeMenu() {
    isMenuOpen = false
  }

  func leave() {
    stop()
    model.router.leaveTable()
  }

  var actions: TableActions {
    var actions = TableActions()
    actions.tableMenu = { [weak self] in self?.toggleMenu() }
    guard !isMenuOpen else { return actions }
    actions.hint = { [weak self] in self?.hint() }
    actions.fold = { [weak self] in self?.fold() }
    actions.checkCall = { [weak self] in self?.checkCall() }
    actions.raise = { [weak self] in self?.raise() }
    actions.confirm = { [weak self] in self?.confirm() }
    actions.nextHand = { [weak self] in self?.nextHand() }
    actions.sizeStep = { [weak self] delta in self?.step(delta) }
    actions.preset = { [weak self] index in self?.preset(index) }
    return actions
  }

  /// Name of the opponent with the biggest bet this street, for the coach's first question.
  var lastBettorName: String {
    let bettor = snapshot.seats.filter { !$0.info.isHero && $0.committed > 0 }.max { $0.committed < $1.committed }
    return bettor?.info.name ?? "the table"
  }
}

private enum TableError: Error { case noBots }
