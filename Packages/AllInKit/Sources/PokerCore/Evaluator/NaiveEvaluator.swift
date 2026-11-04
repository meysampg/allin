/// Slow, obviously-correct reference evaluator. It scores every five-card subset and keeps the best.
///
/// The fast `HandEvaluator` is generated from this type and tested against it.
public enum NaiveEvaluator {
  // MARK: Five-card score

  /// Score of exactly five ranks (0...12). Higher is better. Layout: category in bits 20+, then up to five
  /// 4-bit tiebreak ranks from most to least significant (bits 16, 12, 8, 4, 0).
  static func score(ranks: [Int], flush: Bool) -> UInt32 {
    precondition(ranks.count == 5)
    var counts = [Int](repeating: 0, count: 13)
    for r in ranks { counts[r] += 1 }
    // Groups ordered by (count desc, rank desc): this is also the tiebreak order.
    var groups: [(count: Int, rank: Int)] = []
    for r in 0..<13 where counts[r] > 0 { groups.append((counts[r], r)) }
    groups.sort { $0.count != $1.count ? $0.count > $1.count : $0.rank > $1.rank }

    var straightTop: Int?
    if groups.count == 5 {
      let sorted = groups.map(\.rank).sorted()
      if sorted[4] - sorted[0] == 4 {
        straightTop = sorted[4]
      } else if sorted == [0, 1, 2, 3, 12] {
        straightTop = 3  // the wheel: ace plays low, five-high
      }
    }

    let category: HandCategory
    if flush && straightTop != nil {
      category = .straightFlush
    } else if groups[0].count == 4 {
      category = .fourOfAKind
    } else if groups[0].count == 3 && groups[1].count == 2 {
      category = .fullHouse
    } else if flush {
      category = .flush
    } else if straightTop != nil {
      category = .straight
    } else if groups[0].count == 3 {
      category = .threeOfAKind
    } else if groups[0].count == 2 && groups[1].count == 2 {
      category = .twoPair
    } else if groups[0].count == 2 {
      category = .pair
    } else {
      category = .highCard
    }

    let tiebreak: [Int] = (category == .straight || category == .straightFlush) ? [straightTop!] : groups.map(\.rank)
    var value = UInt32(category.rawValue) << 20
    for (i, r) in tiebreak.enumerated() { value |= UInt32(r) << UInt32(16 - 4 * i) }
    return value
  }

  /// Score of exactly five cards.
  public static func score(five cards: [Card]) -> UInt32 {
    precondition(cards.count == 5)
    let flush = Set(cards.map(\.suit)).count == 1
    return score(ranks: cards.map { Int($0.rank.rawValue) }, flush: flush)
  }

  // MARK: Subsets

  /// All five-card subsets of `cards` (indices into it), in lexicographic order.
  private static func fiveSubsets(_ n: Int) -> [[Int]] {
    precondition(n >= 5)
    var result: [[Int]] = []
    var current: [Int] = []
    func recurse(_ start: Int) {
      if current.count == 5 {
        result.append(current)
        return
      }
      if start >= n { return }
      for i in start..<n {
        current.append(i)
        recurse(i + 1)
        current.removeLast()
      }
    }
    recurse(0)
    return result
  }

  /// The best five-card subset of 5...7 cards: its score and the chosen cards.
  private static func best(_ cards: [Card]) -> (score: UInt32, five: [Card]) {
    precondition((5...7).contains(cards.count), "NaiveEvaluator needs 5 to 7 cards")
    var bestScore: UInt32 = 0
    var bestCards: [Card] = []
    var first = true
    for subset in fiveSubsets(cards.count) {
      let five = subset.map { cards[$0] }
      let s = score(five: five)
      if first || s > bestScore {
        bestScore = s
        bestCards = five
        first = false
      }
    }
    return (bestScore, bestCards)
  }

  // MARK: Public API

  /// Best score (raw, un-ranked) over 5...7 cards.
  public static func bestScore(_ cards: [Card]) -> UInt32 { best(cards).score }

  /// Evaluates 5...7 distinct cards.
  public static func evaluate(_ cards: [Card]) -> HandValue {
    HandClasses.shared.value(forScore: best(cards).score)
  }

  /// The five cards that make the best hand, ordered by significance (see `arrange`).
  public static func bestFive(_ cards: [Card]) -> [Card] { arrange(best(cards).five) }

  /// Orders a five-card hand by significance: grouped cards first (quads, trips, pairs), then kickers, each group
  /// high to low; straights run high to low with the ace last in the wheel.
  static func arrange(_ five: [Card]) -> [Card] {
    var counts = [Int](repeating: 0, count: 13)
    for c in five { counts[Int(c.rank.rawValue)] += 1 }
    let ordered = five.sorted { a, b in
      let ca = counts[Int(a.rank.rawValue)]
      let cb = counts[Int(b.rank.rawValue)]
      if ca != cb { return ca > cb }
      if a.rank != b.rank { return a.rank > b.rank }
      return a.index < b.index
    }
    let ranks = Set(ordered.map { Int($0.rank.rawValue) })
    if ranks == [12, 0, 1, 2, 3] {
      // Wheel: move the ace to the end.
      return ordered.filter { $0.rank != .ace } + ordered.filter { $0.rank == .ace }
    }
    return ordered
  }
}

/// The 7,462 distinct five-card hand classes, ranked best (1) to worst (7462), built from `NaiveEvaluator` scores.
struct HandClasses: Sendable {
  static let shared = HandClasses()

  /// Naive scores, index `i` holds the class with `HandValue.rawValue == i + 1` (descending score).
  let scores: [UInt32]
  private let rankByScore: [UInt32: UInt16]

  private init() {
    var found = Set<UInt32>()
    var ranks = [Int](repeating: 0, count: 5)
    // Every multiset of five ranks (at most four of one rank), ranked as a non-flush.
    func recurse(_ slot: Int, _ lowest: Int) {
      if slot == 5 {
        found.insert(NaiveEvaluator.score(ranks: ranks, flush: false))
        if Set(ranks).count == 5 { found.insert(NaiveEvaluator.score(ranks: ranks, flush: true)) }
        return
      }
      for r in lowest..<13 {
        if ranks[0..<slot].filter({ $0 == r }).count == 4 { continue }
        ranks[slot] = r
        recurse(slot + 1, r)
      }
    }
    recurse(0, 0)
    scores = found.sorted(by: >)
    var map: [UInt32: UInt16] = [:]
    for (i, s) in scores.enumerated() { map[s] = UInt16(i + 1) }
    rankByScore = map
  }

  func value(forScore score: UInt32) -> HandValue {
    HandValue(rawValue: rankByScore[score]!)
  }

  func rank(forScore score: UInt32) -> UInt16 { rankByScore[score]! }
}
