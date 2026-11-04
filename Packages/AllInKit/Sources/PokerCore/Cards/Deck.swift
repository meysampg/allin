/// A deck of distinct cards dealt from the front. Value type; shuffling takes an injected generator.
public struct Deck: Sendable, Equatable {
  public private(set) var cards: [Card]
  private var position: Int

  /// A standard 52-card deck in index order, or a deck without the given known (dead) cards.
  public init(removing known: CardSet = CardSet()) {
    cards = Card.all.filter { !known.contains($0) }
    position = 0
  }

  /// Cards left to deal.
  public var remaining: Int { cards.count - position }
  public var isEmpty: Bool { remaining == 0 }

  /// The undealt cards in deal order.
  public var undealt: ArraySlice<Card> { cards[position...] }

  /// Fisher-Yates shuffle of the undealt cards.
  public mutating func shuffle(using rng: inout some RandomNumberGenerator) {
    guard remaining > 1 else { return }
    var i = cards.count - 1
    while i > position {
      let j = position + Int(rng.next(upperBound: UInt64(i - position + 1)))
      cards.swapAt(i, j)
      i -= 1
    }
  }

  /// Deals the next card, or nil when empty.
  public mutating func deal() -> Card? {
    guard position < cards.count else { return nil }
    defer { position += 1 }
    return cards[position]
  }

  /// Deals `n` cards, or nil (dealing nothing) when fewer remain.
  public mutating func deal(_ n: Int) -> [Card]? {
    guard n >= 0, remaining >= n else { return nil }
    defer { position += n }
    return Array(cards[position..<position + n])
  }

  /// Removes known cards from the undealt part (for example hole cards seen by a player).
  public mutating func remove(_ known: CardSet) {
    let rest = cards[position...].filter { !known.contains($0) }
    cards = Array(cards[..<position]) + rest
  }
}
