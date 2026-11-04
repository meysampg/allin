import Foundation
import Testing

@testable import PokerCore
@testable import PokerEquity

private let preflopHeavyIsOptimized: Bool = {
  #if DEBUG
    false
  #else
    true
  #endif
}()

@Suite("Heavy preflop table", .enabled(if: preflopHeavyIsOptimized)) struct HeavyPreflopTableTests {
  private func pair(_ rng: inout SeededRNG) -> ([Card], [Card]) {
    let deck = Card.all.shuffled(using: &rng)
    return ([deck[0], deck[1]], [deck[2], deck[3]])
  }

  @Test func tableMatchesExactEnumerationForTwentyPairs() async throws {
    let table = try #require(PreflopEquityTable.shared)
    var rng = SeededRNG(seed: 2026)
    var pairs: [([Card], [Card])] = []
    for _ in 0..<20 { pairs.append(pair(&rng)) }
    let exact = await withTaskGroup(of: (Int, Double).self) { group in
      for (i, p) in pairs.enumerated() {
        group.addTask { (i, EquityCalculator.exact([p.0, p.1], board: [])[0].equity) }
      }
      var out = [Double](repeating: 0, count: pairs.count)
      for await (i, e) in group { out[i] = e }
      return out
    }
    for (i, p) in pairs.enumerated() {
      let got = try #require(table.equity(p.0, p.1))
      #expect(abs(got.equity - exact[i]) <= 1.0 / 65535 + 1e-9, "pair \(i): \(p.0) vs \(p.1)")
    }
  }

  @Test func lookupIsFast() throws {
    let table = try #require(PreflopEquityTable.shared)
    var rng = SeededRNG(seed: 7)
    var sample: [([Card], [Card])] = []
    for _ in 0..<1000 { sample.append(pair(&rng)) }
    var sink = 0.0
    let start = ContinuousClock.now
    for round in 0..<1000 {
      for p in sample { sink += table.equity(p.0, p.1)?.equity ?? 0 }
      _ = round
    }
    let d = ContinuousClock.now - start
    let perLookupNs = (Double(d.components.seconds) * 1e9 + Double(d.components.attoseconds) / 1e9) / 1_000_000
    #expect(sink > 0)
    #expect(perLookupNs < 2000, "average \(perLookupNs) ns per lookup")
  }

  @Test func orderingCorrelatesWithTableEquityVersusRandomHand() throws {
    let table = try #require(PreflopEquityTable.shared)
    var equities = [Double](repeating: 0, count: 169)
    for cls in HandClass.all {
      var sum = 0.0
      var n = 0
      for h in cls.combos {
        for v in Combo.all where v.mask.bits & h.mask.bits == 0 {
          sum += try #require(table.equity(h.cards, v.cards)).equity
          n += 1
        }
      }
      equities[cls.gridIndex] = sum / Double(n)
    }
    let ordering = PreflopOrdering.standard
    let byEquity = HandClass.all.sorted { equities[$0.gridIndex] > equities[$1.gridIndex] }
    var equityRank = [Int](repeating: 0, count: 169)
    for (r, c) in byEquity.enumerated() { equityRank[c.gridIndex] = r }
    var sumSq = 0.0
    for c in HandClass.all {
      let d = Double(equityRank[c.gridIndex] - ordering.rank(of: c))
      sumSq += d * d
    }
    let n = 169.0
    let rho = 1 - 6 * sumSq / (n * (n * n - 1))
    #expect(rho >= 0.97, "Spearman \(rho)")
  }
}
