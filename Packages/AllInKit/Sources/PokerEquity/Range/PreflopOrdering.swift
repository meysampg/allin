import PokerCore

/// A strongest-first ranking of the 169 starting hand classes, used to turn "top 15%" into a range.
public struct PreflopOrdering: Sendable, Hashable {
  /// Classes ordered by all-in equity against one random hand, strongest first.
  /// Generated once with a throwaway test: 200k Monte Carlo deals per class (SeededRNG, HandEvaluator),
  /// sorted by equity descending, ties broken suited before offsuit.
  public static let standard = PreflopOrdering(
    classes: standardClassNames.map { try! HandClass($0) })

  private static let standardClassNames: [String] = [
    "AA", "KK", "QQ", "JJ", "TT", "99", "88", "AKs", "77", "AQs", "AJs", "AKo", "ATs",
    "AQo", "AJo", "KQs", "66", "A9s", "ATo", "KJs", "A8s", "KTs", "KQo", "A7s", "KJo",
    "A9o", "55", "QJs", "A6s", "A5s", "K9s", "A8o", "KTo", "QTs", "A7o", "A4s", "A3s",
    "K8s", "QJo", "K9o", "Q9s", "A5o", "A6o", "JTs", "A2s", "K7s", "44", "QTo", "A4o",
    "K6s", "Q8s", "K8o", "A3o", "K5s", "J9s", "Q9o", "K7o", "JTo", "A2o", "K4s", "Q7s",
    "K6o", "T9s", "K3s", "J8s", "33", "Q6s", "Q8o", "K2s", "J9o", "K5o", "Q5s", "J7s",
    "T8s", "K4o", "Q4s", "Q7o", "J8o", "T9o", "K3o", "Q3s", "Q6o", "98s", "J6s", "K2o",
    "T7s", "22", "Q2s", "J5s", "Q5o", "T8o", "J7o", "Q4o", "97s", "T6s", "J4s", "Q3o",
    "J3s", "87s", "98o", "T7o", "J6o", "J2s", "96s", "Q2o", "J5o", "T5s", "97o", "86s",
    "T4s", "T6o", "J4o", "95s", "T3s", "76s", "J3o", "87o", "T2s", "85s", "96o", "J2o",
    "T5o", "94s", "75s", "T4o", "65s", "86o", "93s", "95o", "T3o", "84s", "92s", "76o",
    "74s", "T2o", "54s", "85o", "64s", "83s", "94o", "75o", "82s", "73s", "65o", "93o",
    "63s", "53s", "84o", "92o", "74o", "43s", "72s", "54o", "52s", "64o", "62s", "83o",
    "82o", "42s", "73o", "53o", "32s", "63o", "43o", "72o", "52o", "62o", "42o", "32o",
  ]

  public let classes: [HandClass]
  private let rankByGrid: [Int]
  private let percentileByGrid: [Double]

  /// Precondition: `classes` is a permutation of all 169 classes.
  public init(classes: [HandClass]) {
    precondition(classes.count == 169 && Set(classes).count == 169, "Ordering must list all 169 classes once")
    self.classes = classes
    var rank = [Int](repeating: 0, count: 169)
    var pct = [Double](repeating: 0, count: 169)
    var cumulative = 0
    for (i, c) in classes.enumerated() {
      rank[c.gridIndex] = i
      pct[c.gridIndex] = (Double(cumulative) + Double(c.comboCount) / 2) / 1326
      cumulative += c.comboCount
    }
    rankByGrid = rank
    percentileByGrid = pct
  }

  /// 0 = best.
  public func rank(of c: HandClass) -> Int { rankByGrid[c.gridIndex] }

  /// Midpoint of the class's cumulative combo band, in (0, 1); AA is about 0.0023.
  public func percentile(of c: HandClass) -> Double { percentileByGrid[c.gridIndex] }

  public func percentile(of combo: Combo) -> Double { percentile(of: combo.handClass) }

  /// Deterministic local swaps of neighbours (shape noise); `amount` 0 is the identity.
  /// The probability of swapping positions i and i+1 is `amount * 0.5`. AA and KK never move.
  public func perturbed(seed: UInt64, amount: Double) -> PreflopOrdering {
    guard amount > 0 else { return self }
    var rng = SeededRNG(seed: seed)
    var result = classes
    let p = min(max(amount, 0), 1) * 0.5
    let pinned: Set<HandClass> = [
      HandClass(high: .ace, low: .ace, suited: false)!, HandClass(high: .king, low: .king, suited: false)!,
    ]
    var i = 0
    while i < 168 {
      let roll = Double.random(in: 0..<1, using: &rng)
      if roll < p, !pinned.contains(result[i]), !pinned.contains(result[i + 1]) {
        result.swapAt(i, i + 1)
        i += 2
      } else {
        i += 1
      }
    }
    return PreflopOrdering(classes: result)
  }
}
