import Foundation
import PokerCore
import PokerEquity

/// Card selection for the generator. Everything draws from the caller's `SeededRNG`.
enum CardSampler {
  /// Cards not in `dead`, in index order.
  static func live(excluding dead: CardSet) -> [Card] {
    Card.all.filter { !dead.contains($0) }
  }

  /// A random permutation of the four suits applied to `cards`.
  static func permuteSuits(_ cards: [Card], using rng: inout SeededRNG) -> [Card] {
    let suits = Suit.allCases.shuffled(using: &rng)
    return cards.map { Card(rank: $0.rank, suit: suits[Int($0.suit.rawValue)]) }
  }

  /// A uniformly random combo of two distinct live cards.
  static func randomCombo(from live: [Card], using rng: inout SeededRNG) -> Combo? {
    guard live.count >= 2 else { return nil }
    let i = Int.random(in: 0..<live.count, using: &rng)
    var j = Int.random(in: 0..<(live.count - 1), using: &rng)
    if j >= i { j += 1 }
    return Combo(live[i], live[j])
  }

  /// A uniformly random live combo that satisfies `accept`, found by rejection sampling (120 draws); nil when
  /// the draws all miss, so the caller tries another board.
  static func pickCombo(
    from live: [Card], using rng: inout SeededRNG, accept: (Combo) -> Bool
  ) -> Combo? {
    for _ in 0..<120 {
      guard let combo = randomCombo(from: live, using: &rng) else { return nil }
      if accept(combo) { return combo }
    }
    return nil
  }

  /// A board of `predicate.street` that starts with `prefix`, completed from `live`; nil when 100 random
  /// completions all fail the predicate.
  static func board(
    matching predicate: BoardPredicate, prefix: [Card], live: [Card], using rng: inout SeededRNG
  ) -> [Card]? {
    let needed = predicate.street.boardCount - prefix.count
    guard needed >= 0, live.count >= needed else { return nil }
    if needed == 0 { return predicate.matches(prefix) ? prefix : nil }
    for _ in 0..<100 {
      var pool = live
      var board = prefix
      for _ in 0..<needed {
        board.append(pool.remove(at: Int.random(in: 0..<pool.count, using: &rng)))
      }
      if predicate.matches(board) { return board }
    }
    return nil
  }
}
