import PokerCore

/// A seat that plays a fixed list of actions or a closure, and records what it saw.
public actor ScriptedSeat: Seat {
  public nonisolated let id: SeatID
  public private(set) var observed: [LoggedEvent] = []
  public private(set) var requests: [DecisionRequest] = []

  private var queue: [Action]
  private let responder: (@Sendable (DecisionRequest) -> Action)?

  /// Plays `actions` in order; once exhausted, checks if legal, else folds.
  public init(id: SeatID, actions: [Action]) {
    self.id = id
    queue = actions
    responder = nil
  }

  public init(id: SeatID, decide: @escaping @Sendable (DecisionRequest) -> Action) {
    self.id = id
    queue = []
    responder = decide
  }

  public func observe(_ event: LoggedEvent) async { observed.append(event) }

  public func decide(_ request: DecisionRequest) async -> Action {
    requests.append(request)
    if let responder { return responder(request) }
    if !queue.isEmpty { return queue.removeFirst() }
    return request.legal.canCheck ? .check : .fold
  }
}
