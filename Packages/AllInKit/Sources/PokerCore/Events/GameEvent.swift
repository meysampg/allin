import CryptoKit

/// Identifies a hand in an archive or a session.
public struct HandID: Codable, Sendable, Hashable, ExpressibleByIntegerLiteral, CustomStringConvertible {
  public let rawValue: UInt64
  public init(_ rawValue: UInt64) { self.rawValue = rawValue }
  public init(integerLiteral value: UInt64) { rawValue = value }
  public var description: String { String(rawValue) }
}

/// Public facts about how a hand began. The seed and the deck are not here (see ``GameEvent/deckSetup(seed:deck:)``).
public struct HandStart: Codable, Sendable, Hashable {
  public let config: TableConfig
  public let button: Int
  public let smallBlindSeat: Int
  public let bigBlindSeat: Int
  /// Stacks before any posting, by ascending seat.
  public let seats: [SeatStart]
  public let burnsCards: Bool
  /// SHA-256 of the deck order (one byte per card), as lowercase hex. The host can prove the deck afterwards.
  public let deckCommitment: String

  /// The commitment for a deck order.
  public static func commitment(for deck: [Card]) -> String {
    SHA256.hash(data: deck.map(\.index)).map { String(format: "%02x", $0) }.joined()
  }
}

/// An accepted action with its effect.
public struct ActionTaken: Codable, Sendable, Hashable {
  public let seat: Int
  public let action: Action
  public let chipsAdded: Int
  public let committedAfter: Int
  public let stackAfter: Int
  public let potAfter: Int
  public let isAllIn: Bool
  public let isFullRaise: Bool
  public let isIncompleteRaise: Bool
}

/// A main or side pot.
public struct PotInfo: Codable, Sendable, Hashable {
  public let amount: Int
  public let eligibleSeats: [Int]
}

/// One hand tabled at showdown (or mucked, in the host-only event).
public struct Reveal: Codable, Sendable, Hashable {
  public let seat: Int
  public let holeCards: [Card]
  /// ``HandValue/rawValue`` (1 best ... 7462 worst).
  public let valueRank: UInt16
  public let bestFive: [Card]

  public var value: HandValue { HandValue(rawValue: valueRank) }
}

/// What one pot paid out.
public struct PotAwardInfo: Codable, Sendable, Hashable {
  public let potIndex: Int
  public let amount: Int
  public let eligibleSeats: [Int]
  public let winners: [Int]
  public let shares: [SeatChips]
}

/// The serializable event vocabulary of a hand, mapped one-to-one (plus the host-only extras) from ``HandRecord``.
///
/// Each case has a fixed ``visibility``, so what a seat may see is decided by the type, not by the caller.
public enum GameEvent: Codable, Sendable, Hashable {
  case handStarted(HandStart)
  /// Host-only: the shuffle seed (nil when the deck was supplied) and the full deck in deal order.
  case deckSetup(seed: UInt64?, deck: [Card])
  case blindPosted(Posting)
  /// Private to the seat that holds the cards.
  case holeCardsDealt(seat: Int, cards: [Card])
  case actionRequested(LegalActions)
  case actionTaken(ActionTaken)
  case uncalledBetReturned(seat: Int, amount: Int)
  /// Host-only: the card burned before a street.
  case burned(Street, Card)
  case streetDealt(Street, cards: [Card])
  case potsUpdated([PotInfo])
  /// Public: the hands that had to be shown, in showing order.
  case showdown([Reveal])
  /// Host-only: hands that reached showdown but were allowed to muck.
  case mucked([Reveal])
  case potAwarded(PotAwardInfo)
  case handEnded(HandResult)

  /// Who may see this event.
  public var visibility: Visibility {
    switch self {
    case .holeCardsDealt(let seat, _): .seat(seat)
    case .deckSetup, .burned, .mucked: .hostOnly
    default: .public
    }
  }
}

/// Maps reducer records to events.
///
/// Showdown rule: a live hand must show when any live seat is all-in (everything is tabled), when it wins a share of
/// any pot, or when it ties or beats every hand shown before it in showing order. Every other hand may muck: it is
/// host-only (``GameEvent/mucked(_:)``), so only the host's review can reveal it.
enum EventMapper {
  static func events(for step: HandStep) -> [GameEvent] {
    var out: [GameEvent] = []
    var winners: Set<Int> = []
    for case .potAwarded(let a) in step.records { winners.formUnion(a.winners) }
    for record in step.records {
      switch record {
      case .handStarted(let s):
        let deck = step.state.deck
        out.append(
          .handStarted(
            HandStart(
              config: s.config, button: s.button, smallBlindSeat: s.smallBlindSeat, bigBlindSeat: s.bigBlindSeat,
              seats: s.seats, burnsCards: s.burnsCards, deckCommitment: HandStart.commitment(for: deck))))
        out.append(.deckSetup(seed: s.seed, deck: deck))
      case .posted(let p): out.append(.blindPosted(p))
      case .holeCardsDealt(let seat, let cards): out.append(.holeCardsDealt(seat: seat, cards: cards))
      case .actionRequested(_, let legal): out.append(.actionRequested(legal))
      case .actionApplied(let a, let potAfter):
        out.append(
          .actionTaken(
            ActionTaken(
              seat: a.seat, action: a.action, chipsAdded: a.chipsAdded, committedAfter: a.committedAfter,
              stackAfter: a.stackAfter, potAfter: potAfter, isAllIn: a.isAllIn, isFullRaise: a.isFullRaise,
              isIncompleteRaise: a.isIncompleteRaise)))
      case .uncalledBetReturned(let seat, let amount): out.append(.uncalledBetReturned(seat: seat, amount: amount))
      case .streetDealt(let street, let cards, let burned):
        if let burned { out.append(.burned(street, burned)) }
        out.append(.streetDealt(street, cards: cards))
      case .potsFormed(let pots):
        out.append(.potsUpdated(pots.map { PotInfo(amount: $0.amount, eligibleSeats: $0.eligibleSeats) }))
      case .showdown(let reveals):
        let allIn = step.state.seats.contains { $0.status == .allIn }
        var shown: [Reveal] = []
        var mucked: [Reveal] = []
        var best: HandValue?
        for r in reveals {
          let reveal = Reveal(seat: r.seat, holeCards: r.holeCards, valueRank: r.value.rawValue, bestFive: r.bestFive)
          if allIn || winners.contains(r.seat) || best == nil || r.value >= best! {
            shown.append(reveal)
            if best == nil || r.value > best! { best = r.value }
          } else {
            mucked.append(reveal)
          }
        }
        out.append(.showdown(shown))
        if !mucked.isEmpty { out.append(.mucked(mucked)) }
      case .potAwarded(let a):
        out.append(
          .potAwarded(
            PotAwardInfo(
              potIndex: a.potIndex, amount: a.amount, eligibleSeats: a.eligibleSeats, winners: a.winners,
              shares: a.shares)))
      case .handEnded(let result): out.append(.handEnded(result))
      }
    }
    return out
  }
}
