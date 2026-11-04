/// A player decision. `bet(to:)` and `raise(to:)` carry the player's total committed chips on the current street
/// after the action ("raise to"), not the increment.
public enum Action: Codable, Sendable, Hashable {
  case fold
  case check
  case call
  case bet(to: Int)
  case raise(to: Int)
  /// Commit the whole stack. Resolved as a call for less, a call, an incomplete raise or a full raise.
  case allIn
}

/// Why an action was rejected.
public enum ActionError: Error, Sendable, Equatable {
  /// The betting round is over; nobody is to act.
  case roundClosed
  /// The action kind is not available (e.g. check facing a bet, raise when betting is not reopened).
  case notLegal(Action)
  /// A bet or raise outside `[min, max]`, or not a multiple of the chip unit.
  case amountOutOfRange(Action, min: Int, max: Int)
}
