import PokerCore
import Testing

@testable import PokerEquity

private func cards(_ text: String) -> [Card] { try! Card.parseList(text) }

private func cmb(_ text: String) -> Combo { try! Combo(text) }

private func range(_ text: String) -> HandRange { try! HandRange(parsing: text) }

/// Brute-force heads-up equity of `a` over every board completion with the slow reference evaluator.
private func bruteForce(_ a: [Card], _ b: [Card], board: [Card]) -> Double {
  let used = CardSet(a + b + board)
  let rest = Card.all.filter { !used.contains($0) }
  var runouts: [[Card]] = []
  func build(_ start: Int, _ cur: [Card]) {
    if cur.count == 5 - board.count {
      runouts.append(cur)
      return
    }
    guard start < rest.count else { return }
    for i in start..<rest.count { build(i + 1, cur + [rest[i]]) }
  }
  build(0, [])
  var share = 0.0
  for r in runouts {
    let va = NaiveEvaluator.bestScore(a + board + r)
    let vb = NaiveEvaluator.bestScore(b + board + r)
    if va > vb { share += 1 } else if va == vb { share += 0.5 }
  }
  return share / Double(runouts.count)
}

private func randomSpot(_ rng: inout SeededRNG, boardCount: Int) -> (a: [Card], b: [Card], board: [Card]) {
  var deck = Card.all
  for i in stride(from: deck.count - 1, to: 0, by: -1) { deck.swapAt(i, Int(rng.next(upperBound: UInt64(i + 1)))) }
  return (Array(deck[0..<2]), Array(deck[2..<4]), Array(deck[4..<(4 + boardCount)]))
}

@Suite struct EquityExactTests {
  @Test func exactAgreesWithBruteForce() {
    var rng = SeededRNG(seed: 11)
    for i in 0..<20 {
      let spot = randomSpot(&rng, boardCount: i % 2 == 0 ? 4 : 5)
      let result = EquityCalculator.exact([spot.a, spot.b], board: spot.board)
      #expect(abs(result[0].equity - bruteForce(spot.a, spot.b, board: spot.board)) < 1e-12)
    }
  }

  @Test func equitiesSumToOneAndWinTieAccounting() {
    let hands = [cards("AhKh"), cards("QsQd"), cards("7c7d")]
    let results = EquityCalculator.exact(hands, board: cards("2h9hJc"))
    #expect(abs(results.map(\.equity).reduce(0, +) - 1) < 1e-9)
    #expect(results.allSatisfy { $0.isExact && $0.standardError == 0 && $0.samples == 903 })
    let heads = EquityCalculator.exact([cards("AhKd"), cards("AsKc")], board: cards("2h9hJc"))
    #expect(abs(heads[0].win + heads[1].win + heads[0].tie - 1) < 1e-12)
    #expect(heads[0].tie == heads[1].tie)
  }

  @Test func deadCardsAreExcluded() {
    let dead = CardSet(cards("AcAd"))
    let withDead = EquityCalculator.exact([cards("KhKd"), cards("QsQh")], board: cards("2h9hJc"), dead: dead)
    let without = EquityCalculator.exact([cards("KhKd"), cards("QsQh")], board: cards("2h9hJc"))
    #expect(withDead[0].samples == 903)
    #expect(without[0].samples == 990)
    #expect(withDead[0].equity != without[0].equity)
  }

  @Test func heroVsRangeRemovesBlockedCombos() {
    let hero = cards("AhKh")
    let board = cards("2c7d9s")
    let blocked = EquityCalculator.exact(hero: hero, vs: range("AA"), board: board)
    // AA without the Ah combos is AsAd, AsAc, AdAc: average of three single-hand results.
    let pairs = ["AsAd", "AsAc", "AdAc"].map { EquityCalculator.exact([hero, cards($0)], board: board)[0].equity }
    #expect(abs(blocked.equity - pairs.reduce(0, +) / 3) < 1e-9)
    #expect(blocked.samples == 3 * 990)
  }

  @Test func heroVsRangeMatchesHandVsHandAndWeights() {
    let hero = cards("JhJd")
    let board = cards("2c7d9sKh")
    let single = EquityCalculator.exact(hero: hero, vs: HandRange(combo: cmb("AcKc")), board: board)
    let ref = EquityCalculator.exact([hero, cards("AcKc")], board: board)[0]
    #expect(abs(single.equity - ref.equity) < 1e-12 && abs(single.win - ref.win) < 1e-12)
    // A half-weighted second combo moves the result toward it by exactly its weight share.
    var mixed = HandRange(combo: cmb("AcKc"))
    mixed[cmb("QsQd")] = 0.5
    let r = EquityCalculator.exact(hero: hero, vs: mixed, board: board)
    let other = EquityCalculator.exact([hero, cards("QsQd")], board: board)[0]
    #expect(abs(r.equity - (ref.equity + 0.5 * other.equity) / 1.5) < 1e-9)
  }

  @Test func emptyRangeMeansNothingToBeat() {
    let r = EquityCalculator.exact(hero: cards("AhKh"), vs: .empty, board: cards("2c7d9s"))
    #expect(r.equity == 1 && r.samples == 0)
  }
}

@Suite struct EquityMonteCarloTests {
  @Test func classLevelAcesVsKingsConverges() {
    var rng = SeededRNG(seed: 5)
    let r = EquityCalculator.monteCarlo([range("AA"), range("KK")], board: [], samples: 60_000, using: &rng)
    #expect(abs(r[0].equity - 0.82) < 0.01)
    #expect(abs(r[0].equity + r[1].equity - 1) < 1e-9)
    #expect(r[0].samples == 60_000 && !r[0].isExact && r[0].standardError > 0)
  }

  @Test func monteCarloWithinThreeSigmaOfExactOnFlops() {
    var spotRng = SeededRNG(seed: 99)
    let villain = HandRange.top(0.1)
    for i in 0..<10 {
      let spot = randomSpot(&spotRng, boardCount: 3)
      let exact = EquityCalculator.exact(hero: spot.a, vs: villain, board: spot.board)
      var rng = SeededRNG(seed: UInt64(1000 + i))
      let mc = EquityCalculator.monteCarlo(hero: spot.a, vs: [villain], board: spot.board, samples: 5000, using: &rng)
      #expect(abs(mc.equity - exact.equity) <= 3 * mc.standardError + 1e-9, "spot \(i)")
    }
  }

  @Test func rangeVsRangeSymmetry() {
    let r = range("TT+, AQs+, AKo")
    var rng = SeededRNG(seed: 3)
    let results = EquityCalculator.monteCarlo([r, r], board: cards("Jh4c2d"), samples: 20_000, using: &rng)
    #expect(abs(results[0].equity + results[1].equity - 1) < 1e-9)
    #expect(abs(results[0].equity - 0.5) <= 3 * results[0].standardError)
  }

  @Test func multiwayExactVersusMonteCarlo() {
    let hands = [cards("AhKh"), cards("QsQd"), cards("7c7d")]
    let board = cards("2h9hJc")
    let exact = EquityCalculator.exact(hands, board: board)
    var rng = SeededRNG(seed: 17)
    let mc = EquityCalculator.monteCarlo(
      hands.map { HandRange(combo: Combo($0[0], $0[1])) }, board: board, samples: 20_000, using: &rng)
    for i in 0..<3 { #expect(abs(mc[i].equity - exact[i].equity) <= 3 * mc[i].standardError) }
  }

  @Test func cardRemovalInMonteCarlo() {
    // Hero holds two of the four aces and the board holds a third: only one ace is left for the villain.
    var rng = SeededRNG(seed: 8)
    let r = EquityCalculator.monteCarlo(
      hero: cards("AhAd"), vs: [range("AA")], board: cards("As2c7d"), samples: 500, using: &rng)
    #expect(r.samples == 0)
    var rng2 = SeededRNG(seed: 8)
    let ok = EquityCalculator.monteCarlo(
      hero: cards("AhKd"), vs: [range("AA")], board: cards("2c7d9s"), samples: 500, using: &rng2)
    #expect(ok.samples == 500 && ok.equity < 0.2)
  }

  @Test func determinism() {
    let ranges = [range("22+, A2s+"), range("QQ-88, AJo+")]
    func run(_ seed: UInt64) -> [EquityResult] {
      var rng = SeededRNG(seed: seed)
      return EquityCalculator.monteCarlo(ranges, board: cards("Td5c"), samples: 2000, using: &rng)
    }
    #expect(run(1) == run(1))
    #expect(run(1) != run(2))
  }

  @Test func parallelIsDeterministicAndSized() async {
    let ranges = [range("22+, A2s+"), range("QQ-88, AJo+"), HandRange.full]
    let a = await EquityCalculator.parallelMonteCarlo(ranges, board: cards("Td5c"), samples: 4001, seed: 7, chunks: 5)
    let b = await EquityCalculator.parallelMonteCarlo(ranges, board: cards("Td5c"), samples: 4001, seed: 7, chunks: 5)
    let c = await EquityCalculator.parallelMonteCarlo(ranges, board: cards("Td5c"), samples: 4001, seed: 8, chunks: 5)
    #expect(a == b)
    #expect(a != c)
    #expect(a[0].samples == 4001)
    #expect(abs(a.map(\.equity).reduce(0, +) - 1) < 1e-9)
  }

  @Test func streamIsProgressiveAndEndsFinal() async {
    var estimates: [EquityEstimate] = []
    let stream = EquityCalculator.stream(
      [range("AKs"), range("QQ")], board: [], totalSamples: 5000, batch: 2000, seed: 4)
    for await e in stream { estimates.append(e) }
    #expect(estimates.map(\.samples) == [2000, 4000, 5000])
    #expect(estimates.map(\.isFinal) == [false, false, true])
    #expect(estimates.last?.results.count == 2)
    // Same seed, same stream.
    var again: [EquityEstimate] = []
    for await e in EquityCalculator.stream(
      [range("AKs"), range("QQ")], board: [], totalSamples: 5000, batch: 2000, seed: 4)
    {
      again.append(e)
    }
    #expect(again == estimates)
  }
}

@Suite struct EquityHeroFastPathTests {
  @Test func riverUsesExact() {
    let board = cards("2c7d9sKhQd")
    let villain = range("TT+, AQs+")
    let fast = EquityCalculator.heroEquity(hole: cards("AhKd"), vs: [villain], board: board, samples: 128, seed: 1)
    let exact = EquityCalculator.exact(hero: cards("AhKd"), vs: villain, board: board)
    #expect(fast == exact.equity)
  }

  @Test func deterministicAndSeedSensitive() {
    let v = [range("22+, A2s+, KTo+")]
    let a = EquityCalculator.heroEquity(hole: cards("QhJh"), vs: v, board: cards("2c7d9s"), samples: 128, seed: 9)
    let b = EquityCalculator.heroEquity(hole: cards("QhJh"), vs: v, board: cards("2c7d9s"), samples: 128, seed: 9)
    let c = EquityCalculator.heroEquity(hole: cards("QhJh"), vs: v, board: cards("2c7d9s"), samples: 128, seed: 10)
    #expect(a == b)
    #expect(a != c)
    #expect((0...1).contains(a))
  }

  @Test func closeToExactWithManySamples() {
    let v = range("22+, A2s+, KTo+")
    let exact = EquityCalculator.exact(hero: cards("QhJh"), vs: v, board: cards("2c7d9sTc")).equity
    let fast = EquityCalculator.heroEquity(
      hole: cards("QhJh"), vs: [v], board: cards("2c7d9sTc"), samples: 20_000, seed: 2)
    #expect(abs(fast - exact) < 0.02)
  }

  @Test func multipleVillainsLowerEquity() {
    let v = range("22+, A2s+, KTo+")
    let one = EquityCalculator.heroEquity(hole: cards("AhAd"), vs: [v], board: [], samples: 4000, seed: 3)
    let three = EquityCalculator.heroEquity(hole: cards("AhAd"), vs: [v, v, v], board: [], samples: 4000, seed: 3)
    #expect(three < one)
  }

  @Test func emptyOrDeadRangeReturnsOne() {
    let hole = cards("AhAd")
    #expect(EquityCalculator.heroEquity(hole: hole, vs: [.empty], board: [], samples: 64, seed: 1) == 1)
    #expect(EquityCalculator.heroEquity(hole: hole, vs: [], board: [], samples: 64, seed: 1) == 1)
    // Villain range AcAs is dead when the board holds both.
    let dead = EquityCalculator.heroEquity(
      hole: cards("KhKd"), vs: [range("AcAs")], board: cards("Ac As 2d"), samples: 64, seed: 1)
    #expect(dead == 1)
  }
}

@Suite struct EquitySamplerAndSeedTests {
  @Test func samplerRespectsWeightsAndDeadCards() {
    var r = HandRange()
    r[cmb("AhAd")] = 1
    r[cmb("KhKd")] = 0.25
    let sampler = RangeSampler(r, excluding: CardSet(cards("Qc")))
    var rng = SeededRNG(seed: 21)
    var aces = 0
    for _ in 0..<10_000 where sampler.sample(using: &rng) == cmb("AhAd") { aces += 1 }
    #expect(abs(Double(aces) / 10_000 - 0.8) < 0.03)
    #expect(RangeSampler(r, excluding: CardSet(cards("Ah Kh"))).isEmpty)
    var rng2 = SeededRNG(seed: 1)
    #expect(RangeSampler(.empty, excluding: CardSet()).sample(using: &rng2) == nil)
  }

  @Test func mixIsStableAndSpreads() {
    #expect(StableSeed.mix(1, 2) == StableSeed.mix(1, 2))
    #expect(Set((0..<64).map { StableSeed.mix(42, UInt64($0)) }).count == 64)
    #expect(StableSeed.mix(1, 2) != StableSeed.mix(2, 1))
  }

  @Test func contextSeedFollowsFnv() {
    func make(pot: Int, history: [ActionEntry], hole: String = "AhKh") -> DecisionContext {
      let seats = (0..<2).map {
        SeatView(
          seat: $0, startingStack: 100, stack: 100, committedThisStreet: 0, totalContribution: 0, status: .active)
      }
      let legal = LegalActions.compute(
        seat: 0, stack: 100, committed: 0, currentBet: 0, lastRaiseSize: 2, canRaise: true)
      return DecisionContext(
        config: try! TableConfig(seatCount: 2, smallBlind: 1, bigBlind: 2), seat: 0, holeCards: cards(hole),
        board: cards("2c7d9s"), street: .flop, button: 0, smallBlindSeat: 0, bigBlindSeat: 1, seats: seats, pot: pot,
        history: history, legal: legal)
    }
    // Independent FNV-1a 64 over the documented byte stream (no history).
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    func byte(_ b: UInt8) {
      h ^= UInt64(b)
      h = h &* 0x100_0000_01b3
    }
    func int(_ v: Int) { for i in 0..<8 { byte(UInt8(truncatingIfNeeded: UInt64(v) >> UInt64(8 * i))) } }
    int(0)
    int(1)
    for c in cards("AhKh") + cards("2c7d9s") { byte(c.index) }
    int(10)
    int(0)
    #expect(StableSeed.of(make(pot: 10, history: [])) == h)
    let entry = ActionEntry(street: .preflop, seat: 1, action: .call, chipsAdded: 2, committedAfter: 2, isAllIn: false)
    #expect(StableSeed.of(make(pot: 10, history: [entry])) != h)
    #expect(StableSeed.of(make(pot: 11, history: [])) != h)
    #expect(StableSeed.of(make(pot: 10, history: [], hole: "AhKd")) != h)
  }
}
