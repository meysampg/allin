/// A set of cards as a 52-bit mask; bit `card.index` is set when the card is present.
public struct CardSet: Sendable, Hashable, Sequence, ExpressibleByArrayLiteral, CustomStringConvertible {
  public private(set) var bits: UInt64

  public static let fullMask: UInt64 = (1 << 52) - 1
  public static let full = CardSet(bits: fullMask)

  public init() { bits = 0 }

  /// Creates a set from raw bits; bits above 51 are discarded.
  public init(bits: UInt64) { self.bits = bits & CardSet.fullMask }

  public init(_ cards: some Sequence<Card>) {
    bits = 0
    for c in cards { bits |= 1 << UInt64(c.index) }
  }

  public init(arrayLiteral elements: Card...) { self.init(elements) }

  public var count: Int { bits.nonzeroBitCount }
  public var isEmpty: Bool { bits == 0 }

  public func contains(_ card: Card) -> Bool { bits & (1 << UInt64(card.index)) != 0 }

  /// Inserts a card; returns true when it was not already present.
  @discardableResult
  public mutating func insert(_ card: Card) -> Bool {
    let m: UInt64 = 1 << UInt64(card.index)
    let isNew = bits & m == 0
    bits |= m
    return isNew
  }

  /// Removes a card; returns true when it was present.
  @discardableResult
  public mutating func remove(_ card: Card) -> Bool {
    let m: UInt64 = 1 << UInt64(card.index)
    let was = bits & m != 0
    bits &= ~m
    return was
  }

  public func union(_ other: CardSet) -> CardSet { CardSet(bits: bits | other.bits) }
  public func intersection(_ other: CardSet) -> CardSet { CardSet(bits: bits & other.bits) }
  public func subtracting(_ other: CardSet) -> CardSet { CardSet(bits: bits & ~other.bits) }
  public func isDisjoint(with other: CardSet) -> Bool { bits & other.bits == 0 }
  public func isSubset(of other: CardSet) -> Bool { bits & ~other.bits == 0 }

  /// Cards not in this set.
  public var complement: CardSet { CardSet(bits: ~bits) }

  /// The cards of one suit in this set.
  public func cards(of suit: Suit) -> CardSet {
    var m: UInt64 = 0
    for r in 0..<13 { m |= 1 << UInt64(r * 4 + Int(suit.rawValue)) }
    return CardSet(bits: bits & m)
  }

  /// Cards in ascending index order.
  public func makeIterator() -> Iterator { Iterator(remaining: bits) }

  public struct Iterator: IteratorProtocol, Sendable {
    var remaining: UInt64
    public mutating func next() -> Card? {
      guard remaining != 0 else { return nil }
      let i = remaining.trailingZeroBitCount
      remaining &= remaining &- 1
      return Card(index: UInt8(i))
    }
  }

  public var description: String { Card.format(Array(self)) }
}
