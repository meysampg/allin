import PokerCore

/// One of the 1326 two-card starting hands. The index is `j*(j-1)/2 + i` for card indices `i < j`.
public struct Combo: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
  public static let count = 1326

  /// All combos in index order.
  public static let all: [Combo] = (0..<1326).map { Combo(uncheckedIndex: $0) }

  /// (low card index, high card index) for every combo index.
  private static let cardPairs: [[UInt8]] = {
    var table: [[UInt8]] = []
    table.reserveCapacity(1326)
    for j in 1..<52 {
      for i in 0..<j { table.append([UInt8(i), UInt8(j)]) }
    }
    return table
  }()

  /// Precomputed card-set bits for every combo index.
  static let maskBits: [UInt64] = (0..<1326).map { i in
    let pair = cardPairs[i]
    return (1 as UInt64) << UInt64(pair[0]) | (1 as UInt64) << UInt64(pair[1])
  }

  public let index: Int

  private init(uncheckedIndex: Int) { index = uncheckedIndex }

  /// Creates a combo from two distinct cards in any order.
  public init(_ a: Card, _ b: Card) {
    precondition(a != b, "A combo needs two distinct cards")
    let i = Int(min(a.index, b.index))
    let j = Int(max(a.index, b.index))
    index = j * (j - 1) / 2 + i
  }

  /// Creates a combo from its index. Precondition: `0..<1326`.
  public init(index: Int) {
    precondition((0..<1326).contains(index), "Combo index out of range")
    self.index = index
  }

  /// Parses two cards such as "AhKh" (any order).
  public init(_ text: String) throws {
    let cards = try Card.parseList(text)
    guard cards.count == 2 else { throw CardParseError.invalidLength(text) }
    self.init(cards[0], cards[1])
  }

  /// The card with the larger `Card.index`.
  public var high: Card { Card(index: Combo.cardPairs[index][1]) }
  /// The card with the smaller `Card.index`.
  public var low: Card { Card(index: Combo.cardPairs[index][0]) }
  public var cards: [Card] { [high, low] }
  public var mask: CardSet { CardSet(bits: Combo.maskBits[index]) }

  public var handClass: HandClass { HandClass.all[HandClass.gridIndexByCombo[index]] }

  public var description: String { high.description + low.description }

  public static func < (a: Combo, b: Combo) -> Bool { a.index < b.index }

  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(Int.self)
    guard (0..<1326).contains(raw) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Combo index out of range: \(raw)"))
    }
    self.init(uncheckedIndex: raw)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(index)
  }
}
