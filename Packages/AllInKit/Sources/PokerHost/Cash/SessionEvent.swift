import PokerCore

/// What a session subscriber sees.
public enum SessionEvent: Sendable {
  /// Already filtered for the subscriber's Viewer.
  case hand(LoggedEvent)
  case toppedUp(seat: Int, amount: Int, stackAfter: Int)
  case satOut(seat: Int)
  case satIn(seat: Int)
  case handFinished(HandID, HandResult)
  case ended(SessionSummary)
}

/// Where a session stands.
public struct SessionSummary: Sendable, Hashable {
  public let handsPlayed: Int
  /// Ascending seat.
  public let stacks: [SeatChips]
  /// Initial buy-in plus every top-up, ascending seat.
  public let totalBoughtIn: [SeatChips]

  public init(handsPlayed: Int, stacks: [SeatChips], totalBoughtIn: [SeatChips]) {
    self.handsPlayed = handsPlayed
    self.stacks = stacks
    self.totalBoughtIn = totalBoughtIn
  }

  /// Stack minus total bought in, per seat.
  public var net: [SeatChips] {
    let bought = Dictionary(uniqueKeysWithValues: totalBoughtIn.map { ($0.seat, $0.amount) })
    return stacks.map { SeatChips(seat: $0.seat, amount: $0.amount - (bought[$0.seat] ?? 0)) }
  }
}
