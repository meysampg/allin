/// Fast 5-, 6- and 7-card evaluator built on lookup tables generated at first use (about 170 KB, under 100 ms).
///
/// - Flush path: when a suit holds five or more cards, its 13-bit rank mask indexes an 8,192-entry table.
/// - Non-flush path: the per-rank counts are turned into a perfect hash of the rank multiset (a combinatorial
///   number system over "ways to fill the remaining ranks"), which indexes a table with 6,175 (5 cards), 18,395
///   (6 cards) or 49,205 (7 cards) entries.
///
/// Tables are derived from `NaiveEvaluator`: its scores rank the 6,175 five-card multisets and the 1,287 five-card
/// flush masks; larger hands take the best result of dropping one card.
public enum HandEvaluator {
  /// Evaluates 5...7 distinct cards.
  public static func evaluate(_ cards: CardSet) -> HandValue {
    HandValue(rawValue: tables.rank(of: cards.bits, count: cards.count))
  }

  public static func evaluate(_ cards: [Card]) -> HandValue { evaluate(CardSet(cards)) }

  /// Evaluates hole cards plus board (5...7 cards in total).
  public static func evaluate(hole: [Card], board: [Card]) -> HandValue { evaluate(CardSet(hole + board)) }

  /// The five cards making the best hand, ordered by significance (pairs and trips first, then kickers; straights
  /// high to low with the ace last in a wheel).
  public static func bestFive(_ cards: [Card]) -> [Card] {
    precondition(
      (5...7).contains(cards.count) && CardSet(cards).count == cards.count, "bestFive needs 5 to 7 distinct cards")
    let target = evaluate(cards)
    var chosen: [Card] = []
    var current: [Card] = []
    func search(_ start: Int) -> Bool {
      if current.count == 5 {
        if evaluate(current) == target {
          chosen = current
          return true
        }
        return false
      }
      if start >= cards.count || current.count + (cards.count - start) < 5 { return false }
      for i in start..<cards.count {
        current.append(cards[i])
        if search(i + 1) { return true }
        current.removeLast()
      }
      return false
    }
    _ = search(0)
    return NaiveEvaluator.arrange(chosen)
  }

  /// Size of the generated tables in bytes (for documentation and tests).
  public static var tableByteCount: Int { tables.byteCount }

  /// Forces table generation now, rather than on the first evaluation.
  public static func warmUp() { _ = tables }

  private static let tables = Tables()
}

/// Lookup tables. Allocated once, never freed, read-only after `init`, hence safe to share.
private final class Tables: @unchecked Sendable {
  /// `offs[(rank * 8 + remaining) * 5 + count]`: hash contribution of `count` cards on `rank` when `remaining`
  /// cards are still to be placed on ranks `rank...12`.
  private let offs: UnsafeMutablePointer<UInt32>
  private let flush: UnsafeMutablePointer<UInt16>
  private let nonFlush5: UnsafeMutablePointer<UInt16>
  private let nonFlush6: UnsafeMutablePointer<UInt16>
  private let nonFlush7: UnsafeMutablePointer<UInt16>
  private let sizes: [Int]

  var byteCount: Int { 2 * (8192 + sizes[5] + sizes[6] + sizes[7]) + 4 * 13 * 8 * 5 }

  init() {
    // ways[r][m]: ways to give ranks r...12 counts (0...4 each) summing to m.
    var ways = [[Int]](repeating: [Int](repeating: 0, count: 8), count: 14)
    ways[13][0] = 1
    for r in stride(from: 12, through: 0, by: -1) {
      for m in 0...7 {
        var total = 0
        for c in 0...min(4, m) { total += ways[r + 1][m - c] }
        ways[r][m] = total
      }
    }
    offs = .allocate(capacity: 13 * 8 * 5)
    offs.initialize(repeating: 0, count: 13 * 8 * 5)
    for r in 0..<13 {
      for m in 0...7 {
        var acc = 0
        for c in 0...4 {
          offs[(r * 8 + m) * 5 + c] = UInt32(acc)
          if c <= m { acc += ways[r + 1][m - c] }
        }
      }
    }
    sizes = [0, 0, 0, 0, 0, ways[0][5], ways[0][6], ways[0][7]]
    flush = .allocate(capacity: 8192)
    flush.initialize(repeating: 0, count: 8192)
    nonFlush5 = .allocate(capacity: ways[0][5])
    nonFlush5.initialize(repeating: 0, count: ways[0][5])
    nonFlush6 = .allocate(capacity: ways[0][6])
    nonFlush6.initialize(repeating: 0, count: ways[0][6])
    nonFlush7 = .allocate(capacity: ways[0][7])
    nonFlush7.initialize(repeating: 0, count: ways[0][7])
    generate()
  }

  // MARK: Lookup

  @inline(__always)
  func rank(of bits: UInt64, count n: Int) -> UInt16 {
    precondition(n >= 5 && n <= 7, "HandEvaluator needs 5 to 7 cards")
    let suitMask: UInt64 = 0x1_1111_1111_1111
    for s in 0..<4 {
      let suited = bits & (suitMask << UInt64(s))
      if suited.nonzeroBitCount >= 5 {
        var mask = 0
        for r in 0..<13 { mask |= Int((bits >> UInt64(4 * r + s)) & 1) << r }
        return flush[mask]
      }
    }
    var idx = 0
    var m = n
    for r in 0..<13 {
      let c = Int(((bits >> UInt64(4 * r)) & 15).nonzeroBitCount)
      idx += Int(offs[(r * 8 + m) * 5 + c])
      m -= c
    }
    switch n {
    case 5: return nonFlush5[idx]
    case 6: return nonFlush6[idx]
    default: return nonFlush7[idx]
    }
  }

  private func hash(_ counts: [Int]) -> Int {
    var idx = 0
    var m = counts.reduce(0, +)
    for r in 0..<13 {
      idx += Int(offs[(r * 8 + m) * 5 + counts[r]])
      m -= counts[r]
    }
    return idx
  }

  // MARK: Generation

  private func table(for n: Int) -> UnsafeMutablePointer<UInt16> {
    n == 5 ? nonFlush5 : (n == 6 ? nonFlush6 : nonFlush7)
  }

  private func generate() {
    let classes = HandClasses.shared

    // Flush table. Five-card masks come straight from the naive scorer; 6 and 7 suited cards take the best of
    // dropping one card.
    for size in 5...7 {
      for mask in 0..<8192 where mask.nonzeroBitCount == size {
        if size == 5 {
          let ranks = (0..<13).filter { mask >> $0 & 1 == 1 }
          flush[mask] = classes.rank(forScore: NaiveEvaluator.score(ranks: ranks, flush: true))
        } else {
          var best = UInt16.max
          for r in 0..<13 where mask >> r & 1 == 1 { best = min(best, flush[mask & ~(1 << r)]) }
          flush[mask] = best
        }
      }
    }

    // Non-flush tables by multiset of ranks.
    for n in 5...7 {
      let t = table(for: n)
      var counts = [Int](repeating: 0, count: 13)
      func fill(_ r: Int, _ left: Int) {
        if r == 13 {
          if left != 0 { return }
          let h = hash(counts)
          if n == 5 {
            var ranks: [Int] = []
            for q in 0..<13 { ranks += [Int](repeating: q, count: counts[q]) }
            t[h] = classes.rank(forScore: NaiveEvaluator.score(ranks: ranks, flush: false))
          } else {
            var best = UInt16.max
            let lower = table(for: n - 1)
            for q in 0..<13 where counts[q] > 0 {
              counts[q] -= 1
              best = min(best, lower[hash(counts)])
              counts[q] += 1
            }
            t[h] = best
          }
          return
        }
        for c in 0...min(4, left) {
          counts[r] = c
          fill(r + 1, left - c)
        }
        counts[r] = 0
      }
      fill(0, n)
    }
  }
}
