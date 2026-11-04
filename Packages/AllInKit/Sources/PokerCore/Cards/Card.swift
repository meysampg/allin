/// Card rank, `two` (0) through `ace` (12). The raw value is the rank index used by the evaluator.
public enum Rank: UInt8, CaseIterable, Sendable, Comparable, Hashable {
  case two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace

  public static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }

  /// One-character symbol: 2-9, T, J, Q, K, A.
  public var symbol: Character {
    Rank.symbols[Int(rawValue)]
  }

  public init?(symbol: Character) {
    let up = Character(symbol.uppercased())
    guard let i = Rank.symbols.firstIndex(of: up) else { return nil }
    self.init(rawValue: UInt8(i))
  }

  private static let symbols: [Character] = ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"]
}

/// Card suit. Raw values: clubs 0, diamonds 1, hearts 2, spades 3.
public enum Suit: UInt8, CaseIterable, Sendable, Hashable {
  case clubs, diamonds, hearts, spades

  /// Lowercase symbol: c, d, h, s.
  public var symbol: Character {
    Suit.symbols[Int(rawValue)]
  }

  public init?(symbol: Character) {
    let low = Character(symbol.lowercased())
    guard let i = Suit.symbols.firstIndex(of: low) else { return nil }
    self.init(rawValue: UInt8(i))
  }

  private static let symbols: [Character] = ["c", "d", "h", "s"]
}

/// Errors from parsing cards and card lists.
public enum CardParseError: Error, Sendable, Equatable {
  case invalidLength(String)
  case invalidRank(Character)
  case invalidSuit(Character)
  case duplicateCard(String)
}

/// A playing card encoded as one byte: `rank * 4 + suit` (0...51).
///
/// This lets a card index per-suit and per-rank tables directly and map to bit `index` of a `CardSet`.
public struct Card: Sendable, Hashable, Comparable, CustomStringConvertible {
  /// The compact encoding, 0...51.
  public let index: UInt8

  /// All 52 cards in index order.
  public static let all: [Card] = (0..<52).map { Card(index: UInt8($0)) }

  /// Creates a card from its encoding. Precondition: `index < 52`.
  public init(index: UInt8) {
    precondition(index < 52, "Card index out of range")
    self.index = index
  }

  /// Creates a card from its encoding, or nil when out of range.
  public init?(validating index: Int) {
    guard (0..<52).contains(index) else { return nil }
    self.index = UInt8(index)
  }

  public init(rank: Rank, suit: Suit) {
    self.index = rank.rawValue &* 4 &+ suit.rawValue
  }

  public var rank: Rank { Rank(rawValue: index >> 2)! }
  public var suit: Suit { Suit(rawValue: index & 3)! }

  /// Parses a two-character card such as "As", "Td", "2c" (case-insensitive).
  public init(_ text: String) throws {
    let chars = Array(text)
    guard chars.count == 2 else { throw CardParseError.invalidLength(text) }
    guard let r = Rank(symbol: chars[0]) else { throw CardParseError.invalidRank(chars[0]) }
    guard let s = Suit(symbol: chars[1]) else { throw CardParseError.invalidSuit(chars[1]) }
    self.init(rank: r, suit: s)
  }

  /// Parses a concatenated card list such as "AsKh" or "As Kh Td" (whitespace ignored). Duplicates throw.
  public static func parseList(_ text: String) throws -> [Card] {
    let chars = text.filter { !$0.isWhitespace }
    guard chars.count % 2 == 0 else { throw CardParseError.invalidLength(text) }
    var cards: [Card] = []
    var seen = CardSet()
    var i = chars.startIndex
    while i < chars.endIndex {
      let j = chars.index(i, offsetBy: 2)
      let card = try Card(String(chars[i..<j]))
      guard seen.insert(card) else { throw CardParseError.duplicateCard(card.description) }
      cards.append(card)
      i = j
    }
    return cards
  }

  /// Formats a card list without separators, for example "AsKh".
  public static func format(_ cards: [Card]) -> String {
    cards.map(\.description).joined()
  }

  public var description: String { String([rank.symbol, suit.symbol]) }

  public static func < (a: Card, b: Card) -> Bool { a.index < b.index }
}
