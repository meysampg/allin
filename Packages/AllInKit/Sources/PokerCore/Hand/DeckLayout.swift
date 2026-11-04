/// Builds deck orders for `HandReducer.start(config:button:stacks:deck:burnsCards:)` that deal chosen cards.
public enum DeckLayout {
  /// Seats in hole-card deal order: clockwise from the first seat left of the button, button last
  /// (same as the reducer).
  public static func holeDealOrder(button: Int, seats: [Int]) -> [Int] {
    HandReducer.clockwiseFromButton(seats: seats, button: button)
  }

  /// A 52-card deck. Each seat in `seats` gets `holes[seat]` (exactly 2 cards). The board's first
  /// `board.count` cards (0...5) are `board`. Every other position (burns, later board cards) is
  /// filled from `rest`, in order. `rest` must hold exactly the cards not in `holes` or `board`.
  /// nil if cards repeat, a seat lacks 2 cards or the counts don't add up to 52.
  public static func deck(
    button: Int, seats: [Int], burnsCards: Bool, holes: [Int: [Card]], board: [Card], rest: [Card]
  ) -> [Card]? {
    guard board.count <= 5, !seats.isEmpty, Set(seats).count == seats.count else { return nil }
    var slots = [Card?](repeating: nil, count: 52)
    var used = CardSet()
    var total = 0
    func place(_ card: Card, at position: Int) -> Bool {
      guard position < 52, used.insert(card) else { return false }
      slots[position] = card
      total += 1
      return true
    }

    let order = holeDealOrder(button: button, seats: seats)
    let n = order.count
    for (k, seat) in order.enumerated() {
      guard let hole = holes[seat], hole.count == 2 else { return nil }
      guard place(hole[0], at: k), place(hole[1], at: n + k) else { return nil }
    }

    // Street slots in deal order: (first board index, card count).
    var position = 2 * n
    var boardIndex = 0
    for count in [3, 1, 1] {
      if burnsCards { position += 1 }
      for _ in 0..<count {
        if boardIndex < board.count {
          guard place(board[boardIndex], at: position) else { return nil }
        }
        boardIndex += 1
        position += 1
      }
    }

    var restIterator = rest.makeIterator()
    for i in 0..<52 where slots[i] == nil {
      guard let card = restIterator.next(), place(card, at: i) else { return nil }
    }
    guard restIterator.next() == nil, total == 52 else { return nil }
    return slots.compactMap { $0 }
  }
}
