import PokerCore

/// Public facts needed to rebuild the decision with any hidden cards.
public struct EVSpot: Sendable, Hashable {
  /// From the log's `.handStarted`.
  public let start: HandStart
  /// Every action applied in the hand before the decision, in order.
  public let priorActions: [Action]
  /// The hero's context (hero hole cards, board, legal).
  public let context: DecisionContext

  public init(start: HandStart, priorActions: [Action], context: DecisionContext) {
    self.start = start
    self.priorActions = priorActions
    self.context = context
  }

  public var hero: Int { context.seat }
}
