/// A seat and its stack at the start of a hand.
public struct SeatStart: Codable, Sendable, Hashable {
  public let seat: Int
  public let stack: Int
}

/// What began the hand, for the event log's first record.
public struct HandStartInfo: Sendable, Hashable {
  public let config: TableConfig
  public let button: Int
  public let smallBlindSeat: Int
  public let bigBlindSeat: Int
  /// Stacks before any posting, by ascending seat.
  public let seats: [SeatStart]
  /// Seed of the shuffle, nil when the deck order was supplied.
  public let seed: UInt64?
  public let burnsCards: Bool
}

/// One seat's hand at showdown.
public struct ShowdownReveal: Sendable, Hashable {
  public let seat: Int
  public let holeCards: [Card]
  public let value: HandValue
  /// The best five cards, ordered by significance.
  public let bestFive: [Card]
}

/// What one pot paid out.
public struct PotAwardRecord: Sendable, Hashable {
  public let potIndex: Int
  /// Chips in the pot.
  public let amount: Int
  public let eligibleSeats: [Int]
  /// Winners in odd-chip order (first left of the button first).
  public let winners: [Int]
  /// Chips per winner, odd chips included; sums to `amount`.
  public let shares: [SeatChips]
}

/// A fact produced by the reducer, in the order it happened. M1.6 wraps these as `GameEvent`s.
public enum HandRecord: Sendable, Hashable {
  case handStarted(HandStartInfo)
  /// An ante or blind (chips actually posted, less than nominal for a short stack).
  case posted(Posting)
  case holeCardsDealt(seat: Int, cards: [Card])
  /// A player must act. Emitted after every action that does not end the street, and at the start.
  case actionRequested(seat: Int, legal: LegalActions)
  /// An accepted action, with the pot size after it (antes and all street bets included).
  case actionApplied(AppliedAction, potAfter: Int)
  /// An unmatched part of the biggest bet went back to its owner's stack when the street ended.
  case uncalledBetReturned(seat: Int, amount: Int)
  /// Board cards were dealt (also during an all-in runout). `burned` is host-only information.
  case streetDealt(Street, cards: [Card], burned: Card?)
  /// The main and side pots, computed once the hand is decided.
  case potsFormed([Pot])
  /// Hole cards revealed, in showing order.
  case showdown([ShowdownReveal])
  case potAwarded(PotAwardRecord)
  case handEnded(HandResult)
}

/// The output of one reducer step: the new state and what happened.
public struct HandStep: Sendable, Hashable {
  public let state: HandState
  public let records: [HandRecord]
}
