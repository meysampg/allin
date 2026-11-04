import PokerCore

/// What the host asks a seat when it must act.
public struct DecisionRequest: Sendable, Hashable {
  public let handID: HandID
  /// Seq of the matching `.actionRequested` LoggedEvent.
  public let seq: Int
  public let context: DecisionContext
  /// The host's decision timeout, if any.
  public let deadline: Duration?
  public var legal: LegalActions { context.legal }

  public init(handID: HandID, seq: Int, context: DecisionContext, deadline: Duration?) {
    self.handID = handID
    self.seq = seq
    self.context = context
    self.deadline = deadline
  }
}
