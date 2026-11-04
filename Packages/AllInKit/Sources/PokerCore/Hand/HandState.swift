/// A betting street of Texas Hold'em.
public enum Street: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
  case preflop, flop, turn, river

  public static func < (a: Street, b: Street) -> Bool { a.order < b.order }

  private var order: Int { Street.allCases.firstIndex(of: self)! }

  /// The street after this one, nil after the river.
  public var next: Street? {
    switch self {
    case .preflop: .flop
    case .flop: .turn
    case .turn: .river
    case .river: nil
    }
  }

  /// Community cards dealt when the street starts.
  public var cardsDealt: Int {
    switch self {
    case .preflop: 0
    case .flop: 3
    case .turn, .river: 1
    }
  }
}

/// A seat's chips and cards within one hand.
public struct HandSeat: Codable, Sendable, Hashable {
  public let seat: Int
  /// Stack before antes and blinds.
  public let startingStack: Int
  /// Chips behind. While a betting round is open this is kept in sync after every action.
  public internal(set) var stack: Int
  public internal(set) var holeCards: [Card]
  /// `active` can still act, `allIn` has no further action (it may hold chips returned from an uncalled bet),
  /// `folded` is out of the hand.
  public internal(set) var status: BettingRound.Status
  /// Chips in the pot from antes and from streets already closed (after uncalled-bet returns).
  public internal(set) var settledContribution: Int
}

/// How a hand ended.
public enum HandEndReason: String, Codable, Sendable, Hashable {
  /// Everyone else folded.
  case uncontested
  /// At least two players reached showdown (including all-in runouts).
  case showdown
}

/// Chips attached to a seat. An array of these replaces `[Int: Int]` so results encode stably.
public struct SeatChips: Codable, Sendable, Hashable {
  public let seat: Int
  public let amount: Int
  public init(seat: Int, amount: Int) {
    self.seat = seat
    self.amount = amount
  }
}

/// Final result of a hand.
public struct HandResult: Codable, Sendable, Hashable {
  public let reason: HandEndReason
  public let board: [Card]
  /// Stacks after the hand, by ascending seat.
  public let finalStacks: [SeatChips]
  /// Final minus starting stack (antes and blinds included), by ascending seat. Sums to zero.
  public let net: [SeatChips]
  /// Total chips each seat put in the pot (after uncalled-bet returns).
  public let contributions: [SeatChips]

  public func finalStack(of seat: Int) -> Int? { finalStacks.first { $0.seat == seat }?.amount }
  public func netChips(of seat: Int) -> Int? { net.first { $0.seat == seat }?.amount }
}

/// Where a hand stands.
public enum HandPhase: Codable, Sendable, Hashable {
  /// A player must act; see ``HandState/round``.
  case awaitingAction(seat: Int)
  case complete(HandResult)
}

/// The full, host-side state of one hand (it includes every hole card and the undealt deck, so it is never sent
/// to seats). Change it only through ``HandReducer``.
public struct HandState: Codable, Sendable, Hashable {
  public let config: TableConfig
  public let button: Int
  /// Seed of the shuffle, nil when the deck order was supplied directly.
  public let seed: UInt64?
  /// Whether a card is burned before the flop, turn and river.
  public let burnsCards: Bool
  /// The seats in the hand, ascending.
  public internal(set) var seats: [HandSeat]
  public internal(set) var board: [Card]
  /// The street being played, or the last one reached when the hand is complete.
  public internal(set) var street: Street
  /// The open betting round; nil between streets, during a runout and after the hand.
  public internal(set) var round: BettingRound?
  /// The last seat to bet or raise on the current street (reset when a street with betting starts).
  public internal(set) var lastAggressor: Int?
  public internal(set) var phase: HandPhase
  /// Burned cards so far.
  public internal(set) var burned: [Card]
  /// The whole shuffled deck in deal order and the index of the next card.
  var deck: [Card]
  var deckPosition: Int

  public var undealtCount: Int { deck.count - deckPosition }

  public var isComplete: Bool {
    if case .complete = phase { return true }
    return false
  }

  public var result: HandResult? {
    if case .complete(let r) = phase { return r }
    return nil
  }

  public var seatToAct: Int? {
    if case .awaitingAction(let s) = phase { return s }
    return nil
  }

  /// The options of the player to act.
  public var legalActions: LegalActions? { round?.legalActions() }

  public func seat(_ seat: Int) -> HandSeat? { seats.first { $0.seat == seat } }

  /// Chips a seat has put in the pot so far (settled plus the open street).
  public func contribution(of seat: Int) -> Int {
    (self.seat(seat)?.settledContribution ?? 0) + (round?.player(at: seat)?.committed ?? 0)
  }

  /// Chips in the pot, 0 once the hand is complete and everything was paid out.
  public var pot: Int {
    isComplete ? 0 : seats.reduce(0) { $0 + contribution(of: $1.seat) }
  }

  /// Stacks plus pot. Constant from start to end of a hand.
  public var totalChips: Int { seats.reduce(0) { $0 + $1.stack } + pot }

  /// Seats still in the hand (not folded).
  public var liveSeats: [Int] { seats.filter { $0.status != .folded }.map(\.seat) }
}
