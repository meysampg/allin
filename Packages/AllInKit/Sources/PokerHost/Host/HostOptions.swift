import PokerCore

public struct HostOptions: Sendable, Hashable {
  /// nil = wait forever (sims).
  public var decisionTimeout: Duration?
  /// Safety bound on applied actions in one hand.
  public var maxActionsPerHand: Int

  public init(decisionTimeout: Duration? = nil, maxActionsPerHand: Int = 10_000) {
    self.decisionTimeout = decisionTimeout
    self.maxActionsPerHand = maxActionsPerHand
  }
}

public enum HandDeal: Sendable, Hashable {
  case seed(UInt64)
  case deck([Card])
}

public struct HandSetup: Sendable, Hashable {
  public var handID: HandID
  public var button: Int
  /// Seats dealt in; each needs a registered Seat.
  public var stacks: [SeatStack]
  public var deal: HandDeal
  public var burnsCards: Bool

  public init(handID: HandID, button: Int, stacks: [SeatStack], deal: HandDeal, burnsCards: Bool = true) {
    self.handID = handID
    self.button = button
    self.stacks = stacks
    self.deal = deal
    self.burnsCards = burnsCards
  }
}

public enum HostWarning: Sendable, Hashable {
  case illegalAction(seat: Int, attempted: Action, applied: Action)
  case timedOut(seat: Int, applied: Action)
}

public struct HandOutcome: Sendable {
  public let handID: HandID
  /// Full host log.
  public let log: EventLog
  public let result: HandResult
  public let finalState: HandState
  public let warnings: [HostWarning]

  public init(handID: HandID, log: EventLog, result: HandResult, finalState: HandState, warnings: [HostWarning]) {
    self.handID = handID
    self.log = log
    self.result = result
    self.finalState = finalState
    self.warnings = warnings
  }
}

public enum HostError: Error, Sendable, Equatable {
  case duplicateSeat(Int)
  case seatOutOfRange(Int)
  case noSeatFor(Int)
  case actionLimitExceeded(HandID)
}
