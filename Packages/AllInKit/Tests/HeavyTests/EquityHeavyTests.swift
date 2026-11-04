import Foundation
import Testing

@testable import PokerCore
@testable import PokerEquity

/// Timings only make sense in an optimized build; `swift test -c release --filter Heavy` (Tools/test.sh heavy) runs
/// them. Assertions allow 2x slack over the targets because Swift Testing runs suites concurrently.
private let equityHeavyIsOptimized: Bool = {
  #if DEBUG
    false
  #else
    true
  #endif
}()

private func eqCards(_ text: String) -> [Card] { try! Card.parseList(text) }

private func eqRange(_ text: String) -> HandRange { try! HandRange(parsing: text) }

/// Median wall time in milliseconds over `runs` runs, after one warm-up call.
private func eqMedianMs(runs: Int = 15, _ body: () -> Void) -> Double {
  body()
  var times: [Double] = []
  for _ in 0..<runs {
    let start = ContinuousClock.now
    body()
    let d = ContinuousClock.now - start
    times.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
  }
  times.sort()
  return times[times.count / 2]
}

@Suite("Heavy equity", .enabled(if: equityHeavyIsOptimized)) struct HeavyEquityTests {
  @Test func goldenAcesVersusKingsPreflop() {
    // Every AA combo against every KK combo (36 disjoint pairs): the class-level equity is about 81.95%.
    var sum = 0.0
    var pairs = 0
    for a in HandClass.all[0].combos {
      for k in (try! HandClass("KK")).combos {
        let r = EquityCalculator.exact([a.cards, k.cards], board: [])
        #expect(r[0].samples == 1_712_304 && r[0].isExact)
        #expect(abs(r[0].equity + r[1].equity - 1) < 1e-9)
        sum += r[0].equity
        pairs += 1
      }
    }
    print("equity heavy: AA vs KK class level exact \(sum / Double(pairs))")
    #expect(pairs == 36)
    #expect(abs(sum / Double(pairs) - 0.8195) < 0.003)
  }

  @Test func goldenPreflopMatchups() {
    // Well-known heads-up equities, exact enumeration.
    let cases: [(String, String, Double)] = [
      ("AhKh", "QsQd", 0.4621), ("AhKd", "2c2s", 0.4696), ("7h2d", "AsAc", 0.1258),
    ]
    for (a, b, expected) in cases {
      let r = EquityCalculator.exact([eqCards(a), eqCards(b)], board: [])
      #expect(abs(r[0].equity - expected) < 0.002, "\(a) vs \(b): \(r[0].equity)")
    }
  }

  @Test func convergenceOfClassLevelMonteCarlo() async {
    let r = await EquityCalculator.parallelMonteCarlo(
      [eqRange("AA"), eqRange("KK")], board: [], samples: 400_000, seed: 12)
    #expect(abs(r[0].equity - 0.82) < 0.003)
  }

  @Test func handVersusHandFlopExactTiming() {
    let hands = [eqCards("AhKh"), eqCards("QsQd")]
    let board = eqCards("2h9hJc")
    let ms = eqMedianMs { _ = EquityCalculator.exact(hands, board: board) }
    print("equity heavy: hand vs hand flop exact median \(ms) ms")
    #expect(ms < 5)
  }

  @Test func handVersusFullRangeTurnExactTiming() {
    let hero = eqCards("AhKh")
    let board = eqCards("2h9hJcQd")
    let ms = eqMedianMs { _ = EquityCalculator.exact(hero: hero, vs: .full, board: board) }
    print("equity heavy: hand vs full range turn exact median \(ms) ms")
    #expect(ms < 5)
  }

  @Test func handVersusFullRangeFlopExactTiming() {
    // Documented deviation from PLAN: 60 ms (not 5 ms) for a full range; narrow ranges are far faster.
    let hero = eqCards("AhKh")
    let board = eqCards("2h9hJc")
    let ms = eqMedianMs { _ = EquityCalculator.exact(hero: hero, vs: .full, board: board) }
    print("equity heavy: hand vs full range flop exact median \(ms) ms")
    #expect(ms < 60)
  }

  @Test func rangeVersusRangeMonteCarloTiming() {
    let ranges = [eqRange("22+, A2s+, KTo+, QJs"), eqRange("55+, ATs+, KQ")]
    let board = eqCards("Td5c8h")
    let ms = eqMedianMs {
      var rng = SeededRNG(seed: 1)
      _ = EquityCalculator.monteCarlo(ranges, board: board, samples: 50_000, using: &rng)
    }
    print("equity heavy: range vs range MC 50k median \(ms) ms")
    #expect(ms < 40)
  }

  @Test func sixWayMonteCarloTiming() {
    let ranges = [HandRange](repeating: HandRange.top(0.3), count: 6)
    let ms = eqMedianMs {
      var rng = SeededRNG(seed: 2)
      _ = EquityCalculator.monteCarlo(ranges, board: [], samples: 20_000, using: &rng)
    }
    print("equity heavy: 6-way MC 20k median \(ms) ms")
    #expect(ms < 40)
  }

  @Test func streamFirstValueTiming() async {
    let ranges = [eqRange("22+, A2s+, KTo+"), eqRange("55+, ATs+, KQ")]
    var times: [Double] = []
    for run in 0..<16 {
      let start = ContinuousClock.now
      for await _ in EquityCalculator.stream(ranges, board: [], totalSamples: 100_000, seed: UInt64(run)) {
        let d = ContinuousClock.now - start
        times.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        break
      }
    }
    times.removeFirst()  // warm-up (evaluator tables, task startup)
    times.sort()
    let median = times[times.count / 2]
    print("equity heavy: stream first value median \(median) ms")
    #expect(median < 16)
  }

  @Test func heroEquityTiming() {
    let villain = [eqRange("22+, A2s+, KTo+, QTs+, JTs, T9s")]
    let hole = eqCards("QhJh")
    let board = eqCards("2c7d9s")
    var acc = 0.0
    _ = EquityCalculator.heroEquity(hole: hole, vs: villain, board: board, samples: 128, seed: 0)
    let start = ContinuousClock.now
    for i in 0..<10_000 {
      acc += EquityCalculator.heroEquity(hole: hole, vs: villain, board: board, samples: 128, seed: UInt64(i))
    }
    let d = ContinuousClock.now - start
    let micros = (Double(d.components.seconds) * 1e6 + Double(d.components.attoseconds) / 1e12) / 10_000
    print("equity heavy: heroEquity 128 samples avg \(micros) us (checksum \(acc))")
    #expect(micros <= 80)
  }

  @Test func exactAndMonteCarloAgreeOnRandomSpots() {
    var rng = SeededRNG(seed: 2024)
    var within = 0
    let total = 100
    for i in 0..<total {
      var deck = Card.all
      for k in stride(from: deck.count - 1, to: 0, by: -1) { deck.swapAt(k, Int(rng.next(upperBound: UInt64(k + 1)))) }
      let boardCount = [3, 4, 5][i % 3]
      let hero = Array(deck[0..<2])
      let board = Array(deck[2..<(2 + boardCount)])
      let villain = HandRange.top(0.15 + 0.3 * Double(i % 5) / 4)
      let exact = EquityCalculator.exact(hero: hero, vs: villain, board: board)
      var mcRng = SeededRNG(seed: UInt64(i) &+ 77)
      let mc = EquityCalculator.monteCarlo(hero: hero, vs: [villain], board: board, samples: 50_000, using: &mcRng)
      if abs(mc.equity - exact.equity) <= 3 * mc.standardError + 1e-9 { within += 1 }
    }
    print("equity heavy: \(within)/\(total) spots within 3 sigma")
    #expect(within >= 99)
  }
}
