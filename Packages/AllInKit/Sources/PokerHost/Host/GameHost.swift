import PokerCore
import Synchronization

/// The authoritative, event-sourced host: plays one hand at a time with any mix of seats.
public actor GameHost {
  public nonisolated let config: TableConfig
  private let seats: [SeatID: any Seat]
  private let options: HostOptions

  public init(config: TableConfig, seats: [any Seat], options: HostOptions = HostOptions()) throws {
    var map: [SeatID: any Seat] = [:]
    for seat in seats {
      guard (0..<config.seatCount).contains(seat.id) else { throw HostError.seatOutOfRange(seat.id) }
      guard map[seat.id] == nil else { throw HostError.duplicateSeat(seat.id) }
      map[seat.id] = seat
    }
    self.config = config
    self.seats = map
    self.options = options
  }

  /// Plays one hand to completion. `onEvent` receives every host-view event synchronously, in order (spectator
  /// plumbing). Throws reducer errors (bad setup) or HostError.
  public func playHand(
    _ setup: HandSetup, onEvent: @escaping @Sendable (LoggedEvent) -> Void = { _ in }
  ) async throws -> HandOutcome {
    var dealtIn: [any Seat] = []
    var seen: Set<Int> = []
    for stack in setup.stacks {
      guard (0..<config.seatCount).contains(stack.seat) else { throw HostError.seatOutOfRange(stack.seat) }
      guard seen.insert(stack.seat).inserted else { throw HostError.duplicateSeat(stack.seat) }
      guard let seat = seats[stack.seat] else { throw HostError.noSeatFor(stack.seat) }
      dealtIn.append(seat)
    }
    dealtIn.sort { $0.id < $1.id }

    var step: HandStep
    switch setup.deal {
    case .seed(let seed):
      step = try HandReducer.start(
        config: config, button: setup.button, stacks: setup.stacks, seed: seed, burnsCards: setup.burnsCards)
    case .deck(let deck):
      step = try HandReducer.start(
        config: config, button: setup.button, stacks: setup.stacks, deck: deck, burnsCards: setup.burnsCards)
    }
    var log = EventLog(handID: setup.handID)
    var records = step.records
    var warnings: [HostWarning] = []
    var actionCount = 0

    var requestSeq = await emit(step, into: &log, to: dealtIn, onEvent)
    while let actor = step.state.seatToAct {
      guard let seat = seats[actor], let seq = requestSeq,
        let context = DecisionContext.make(
          from: step.state, for: actor, history: ActionEntry.entries(from: records))
      else { throw HostError.noSeatFor(actor) }
      let request = DecisionRequest(
        handID: setup.handID, seq: seq, context: context, deadline: options.decisionTimeout)
      var action: Action
      if let timeout = options.decisionTimeout {
        if let answer = await Self.decide(seat, request, timeout: timeout) {
          action = answer
        } else {
          action = Self.fallback(context.legal)
          warnings.append(.timedOut(seat: actor, applied: action))
        }
      } else {
        action = await seat.decide(request)
      }
      if !context.legal.isLegal(action) {
        let applied = Self.fallback(context.legal)
        warnings.append(.illegalAction(seat: actor, attempted: action, applied: applied))
        action = applied
      }
      actionCount += 1
      if actionCount > options.maxActionsPerHand { throw HostError.actionLimitExceeded(setup.handID) }
      step = try HandReducer.apply(action, to: step.state)
      records += step.records
      requestSeq = await emit(step, into: &log, to: dealtIn, onEvent)
    }
    guard let result = step.state.result else { throw HostError.actionLimitExceeded(setup.handID) }
    return HandOutcome(
      handID: setup.handID, log: log, result: result, finalState: step.state, warnings: warnings)
  }

  /// Appends the step to the host log, then delivers each new event to the listener and the seats that may see it.
  /// Returns the seq of the last `.actionRequested` among them.
  private func emit(
    _ step: HandStep, into log: inout EventLog, to dealtIn: [any Seat], _ onEvent: @Sendable (LoggedEvent) -> Void
  ) async -> Int? {
    let events = log.append(step)
    var lastRequest: Int?
    for event in events {
      onEvent(event)
      if case .actionRequested = event.event { lastRequest = event.seq }
    }
    for event in events {
      for seat in dealtIn where Viewer.seat(seat.id).canSee(event.visibility) {
        await seat.observe(event)
      }
    }
    return lastRequest
  }

  private static func fallback(_ legal: LegalActions) -> Action { legal.canCheck ? .check : .fold }

  /// Asks `seat`, giving up after `timeout`. Unstructured tasks, so a seat that ignores cancellation cannot
  /// hold the host: the first to finish wins and a late answer is dropped.
  private static func decide(_ seat: any Seat, _ request: DecisionRequest, timeout: Duration) async -> Action? {
    await withCheckedContinuation { (continuation: CheckedContinuation<Action?, Never>) in
      let race = Race()
      let asker = Task {
        let answer = await seat.decide(request)
        if race.claim() {
          continuation.resume(returning: answer)
          race.cancelAll()
        }
      }
      let timer = Task {
        try? await Task.sleep(for: timeout)
        if !Task.isCancelled, race.claim() {
          continuation.resume(returning: nil)
          race.cancelAll()
        }
      }
      race.register([asker, timer])
    }
  }
}

/// First-finisher gate for the timeout race.
private final class Race: Sendable {
  private struct State {
    var resumed = false
    var tasks: [Task<Void, Never>] = []
  }
  private let state = Mutex(State())

  /// True for the first caller only.
  func claim() -> Bool {
    state.withLock { s in
      if s.resumed { return false }
      s.resumed = true
      return true
    }
  }

  func register(_ tasks: [Task<Void, Never>]) {
    let alreadyDone = state.withLock { s -> Bool in
      s.tasks = tasks
      return s.resumed
    }
    if alreadyDone { tasks.forEach { $0.cancel() } }
  }

  func cancelAll() {
    let tasks = state.withLock { $0.tasks }
    tasks.forEach { $0.cancel() }
  }
}
