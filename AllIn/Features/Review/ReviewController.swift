import AllInStore
import Foundation
import OSLog
import Observation
import PokerAnalysis
import PokerCore
import TableKit

/// Loads a hand and its grades, owns the mini table and drives the replays.
@MainActor @Observable
final class ReviewController {
  enum Phase: Equatable {
    case loading
    case grading
    case ready
    case failed(String)
  }

  let request: ReviewRequest
  let scene: TableScene
  private(set) var phase: Phase = .loading
  private(set) var analysis: HandAnalysis?
  private(set) var selection: Int?
  private(set) var isReplaying = false
  private(set) var savedSpots: Set<String> = []

  @ObservationIgnored private let model: AppModel
  @ObservationIgnored private var snapshots: ReviewSnapshots?
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var replayTask: Task<Void, Never>?
  @ObservationIgnored private var handKey = ""

  private static let log = Logger(subsystem: "app.allin", category: "ReviewController")

  init(request: ReviewRequest, model: AppModel, systemReduceMotion: Bool) {
    self.request = request
    self.model = model
    let timing = AnimationTiming(
      speedFactor: model.launch.fast ? 0.1 : 0.6, reduceMotion: model.effectiveReduceMotion(system: systemReduceMotion))
    let options = TableSceneOptions(
      timing: timing, hud: .basic, fourColorDeck: model.settings.fourColorDeck, driver: .spriteKit, mode: .replay)
    scene = TableScene(resolver: model.themeResolver, options: options, soundBank: nil)
    savedSpots = Set(model.progress.savedSpots().map(\.key))
  }

  // MARK: Loading

  func start() {
    guard loadTask == nil else { return }
    loadTask = Task { [weak self] in await self?.load() }
  }

  func stop() {
    loadTask?.cancel()
    replayTask?.cancel()
    loadTask = nil
    replayTask = nil
    scene.cancelAnimations()
  }

  private func load() async {
    switch request {
    case .archived(let key):
      await loadArchived(key)
    case .demo(let seed):
      await loadDemo(seed)
    }
  }

  private func loadArchived(_ key: ArchiveKey) async {
    handKey = key.rawValue
    let hand: ArchivedHand?
    do {
      hand = try model.archive.hand(key)
    } catch {
      Self.log.error("could not read \(key.rawValue): \(String(describing: error))")
      hand = nil
    }
    guard let hand else {
      phase = .failed("This hand is no longer in the archive.")
      return
    }
    let seats = hand.seats.map {
      TableSeatInfo(seat: $0.seat, name: $0.name, characterID: $0.characterID, styleHint: $0.style, isHero: $0.isHero)
    }
    guard prepareTable(log: hand.log, heroSeat: hand.heroSeat, seats: seats) else { return }
    phase = .grading
    while !Task.isCancelled {
      if let analysis = model.analysis.analysis(for: key) {
        finish(analysis)
        return
      }
      if !model.analysis.pending.contains(key) {
        phase = .failed("Hoot could not analyze this hand.")
        return
      }
      try? await Task.sleep(for: .milliseconds(400))
    }
  }

  private func loadDemo(_ seed: UInt64) async {
    guard let golden = try? GoldenHands.reviewDemo() else {
      phase = .failed("The demo hand could not be built.")
      return
    }
    handKey = "demo#\(golden.log.handID.rawValue)"
    let seats = Self.seatInfos(golden: golden, model: model)
    guard prepareTable(log: golden.log, heroSeat: golden.heroSeat, seats: seats) else { return }
    phase = .grading
    do {
      let (_, analysis) = try await model.analysis.analyzeDemo(seed: seed)
      guard !Task.isCancelled else { return }
      finish(analysis)
    } catch {
      Self.log.error("demo analysis failed: \(String(describing: error))")
      phase = .failed("Hoot could not analyze this hand.")
    }
  }

  private static func seatInfos(golden: GoldenHand, model: AppModel) -> [TableSeatInfo] {
    var count = 6
    for logged in golden.log.events {
      if case .handStarted(let start) = logged.event {
        count = start.config.seatCount
        break
      }
    }
    return (0..<count).map { seat in
      if seat == golden.heroSeat {
        return TableSeatInfo(seat: seat, name: "You", characterID: "you", styleHint: nil, isHero: true)
      }
      let id = golden.characters[seat]
      let character = id.flatMap { model.character($0) }
      return TableSeatInfo(
        seat: seat, name: character?.name ?? id?.capitalized ?? "Seat \(seat)", characterID: id,
        styleHint: character?.style, isHero: false)
    }
  }

  /// Shows the finished hand, villains' cards revealed, while the grades are still being computed.
  private func prepareTable(log: EventLog, heroSeat: Int, seats: [TableSeatInfo]) -> Bool {
    guard let snapshots = ReviewSnapshots(log: log, heroSeat: heroSeat, seats: seats) else {
      phase = .failed("This hand's record is incomplete.")
      return false
    }
    self.snapshots = snapshots
    scene.configure(table: snapshots.config, seats: seats, heroSeat: heroSeat)
    scene.show(snapshots.snapshot())
    return true
  }

  private func finish(_ analysis: HandAnalysis) {
    self.analysis = analysis
    phase = .ready
    selection = analysis.initialSelection
    showSelectedSpot()
  }

  // MARK: Selection

  var selectedDecision: ReviewedDecision? {
    guard let analysis, let selection, analysis.decisions.indices.contains(selection) else { return nil }
    return analysis.decisions[selection]
  }

  var handNumber: UInt64 { analysis?.handID.rawValue ?? snapshots?.heroEvents.first?.handID.rawValue ?? 0 }

  func select(_ index: Int) {
    guard let analysis, analysis.decisions.indices.contains(index) else { return }
    selection = index
    showSelectedSpot()
  }

  func step(_ delta: Int) {
    guard let analysis, !analysis.decisions.isEmpty else { return }
    let current = selection ?? 0
    select(min(max(current + delta, 0), analysis.decisions.count - 1))
  }

  var canStepBack: Bool { (selection ?? 0) > 0 }
  var canStepForward: Bool { (selection ?? 0) < (analysis?.decisions.count ?? 0) - 1 }

  private func showSelectedSpot() {
    cancelReplay()
    guard let snapshots, let decision = selectedDecision else { return }
    scene.show(snapshots.snapshot(at: decision.requestSeq))
  }

  // MARK: Replay

  /// The whole hand from the deal, then the revealed final position.
  func replayHand() {
    runReplay(from: nil, through: nil)
  }

  /// From the start of the decision's street up to the decision.
  func replaySpot() {
    guard let decision = selectedDecision else { return }
    runReplay(from: decision.street, through: decision.requestSeq)
  }

  private func cancelReplay() {
    replayTask?.cancel()
    replayTask = nil
    isReplaying = false
    scene.cancelAnimations()
  }

  private func runReplay(from street: Street?, through seq: Int?) {
    guard let snapshots else { return }
    cancelReplay()
    isReplaying = true
    let scene = scene
    replayTask = Task { [weak self] in
      scene.configure(table: snapshots.config, seats: snapshots.seats, heroSeat: snapshots.heroSeat)
      var first = 0
      if let street, let start = snapshots.streetStart(street) {
        // Bring the scene to the street's start without animating.
        scene.enqueue(contentsOf: snapshots.events(in: 0...max(0, start - 1)))
        scene.cancelAnimations()
        first = start
      }
      scene.enqueue(contentsOf: snapshots.events(in: first...max(first, seq ?? snapshots.lastSeq)))
      await scene.waitUntilIdle()
      guard !Task.isCancelled else { return }
      scene.show(snapshots.snapshot(at: seq))
      self?.isReplaying = false
    }
  }

  // MARK: Gym

  func isSaved(_ decision: ReviewedDecision) -> Bool {
    savedSpots.contains(spotKey(decision))
  }

  func addToGym(_ decision: ReviewedDecision) {
    let key = spotKey(decision)
    model.progress.saveSpot(
      StoredSavedSpot(
        key: key, handKey: handKey, decisionIndex: decision.index, streetRaw: decision.street.rawValue,
        title: decision.title, createdAt: .now))
    savedSpots.insert(key)
  }

  private func spotKey(_ decision: ReviewedDecision) -> String { "\(handKey)#\(decision.index)" }
}
