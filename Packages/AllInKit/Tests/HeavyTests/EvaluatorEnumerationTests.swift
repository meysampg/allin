import Testing

@testable import PokerCore

/// Enumerations only make sense in an optimized build; `swift test -c release` (Tools/test.sh heavy) runs them. A
/// debug run (for example `--filter Evaluator`, which matches this file name) skips them.
private let isOptimizedBuild: Bool = {
  #if DEBUG
    false
  #else
    true
  #endif
}()

@Suite("Heavy hand enumeration", .enabled(if: isOptimizedBuild)) struct HeavyHandEnumerationTests {
  /// Category counts indexed by `HandCategory.rawValue`.
  private typealias Counts = [Int]

  @Test func allFiveCardHands() {
    let evaluator = HandEvaluator.self
    var counts = Counts(repeating: 0, count: 9)
    var classes = Set<UInt16>()
    var total = 0
    for a in 0..<48 {
      for b in (a + 1)..<49 {
        for c in (b + 1)..<50 {
          for d in (c + 1)..<51 {
            for e in (d + 1)..<52 {
              let bits: UInt64 = 1 << a | 1 << b | 1 << c | 1 << d | 1 << e
              let v = evaluator.evaluate(CardSet(bits: bits))
              counts[Int(v.category.rawValue)] += 1
              classes.insert(v.rawValue)
              total += 1
            }
          }
        }
      }
    }
    #expect(total == 2_598_960)
    #expect(classes.count == 7462)
    #expect(counts[Int(HandCategory.straightFlush.rawValue)] == 40)
    #expect(counts[Int(HandCategory.fourOfAKind.rawValue)] == 624)
    #expect(counts[Int(HandCategory.fullHouse.rawValue)] == 3744)
    #expect(counts[Int(HandCategory.flush.rawValue)] == 5108)
    #expect(counts[Int(HandCategory.straight.rawValue)] == 10200)
    #expect(counts[Int(HandCategory.threeOfAKind.rawValue)] == 54912)
    #expect(counts[Int(HandCategory.twoPair.rawValue)] == 123_552)
    #expect(counts[Int(HandCategory.pair.rawValue)] == 1_098_240)
    #expect(counts[Int(HandCategory.highCard.rawValue)] == 1_302_540)
  }

  @Test func allSevenCardHandsHaveKnownCategoryCountsAndSpeed() {
    var counts = Counts(repeating: 0, count: 9)
    var royal = 0
    var total = 0
    let clock = ContinuousClock()
    let start = clock.now
    for a in 0..<46 {
      let ba: UInt64 = 1 << UInt64(a)
      for b in (a + 1)..<47 {
        let bb = ba | 1 << UInt64(b)
        for c in (b + 1)..<48 {
          let bc = bb | 1 << UInt64(c)
          for d in (c + 1)..<49 {
            let bd = bc | 1 << UInt64(d)
            for e in (d + 1)..<50 {
              let be = bd | 1 << UInt64(e)
              for f in (e + 1)..<51 {
                let bf = be | 1 << UInt64(f)
                for g in (f + 1)..<52 {
                  let v = HandEvaluator.evaluate(CardSet(bits: bf | 1 << UInt64(g)))
                  counts[Int(v.category.rawValue)] += 1
                  if v.rawValue == 1 { royal += 1 }
                  total += 1
                }
              }
            }
          }
        }
      }
    }
    let elapsed = clock.now - start
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let rate = Double(total) / seconds
    print("Heavy: 7-card enumeration \(total) hands in \(seconds) s = \(Int(rate / 1e6)) M evals/s")

    #expect(total == 133_784_560)
    #expect(counts[Int(HandCategory.highCard.rawValue)] == 23_294_460)
    #expect(counts[Int(HandCategory.pair.rawValue)] == 58_627_800)
    #expect(counts[Int(HandCategory.twoPair.rawValue)] == 31_433_400)
    #expect(counts[Int(HandCategory.threeOfAKind.rawValue)] == 6_461_620)
    #expect(counts[Int(HandCategory.straight.rawValue)] == 6_180_020)
    #expect(counts[Int(HandCategory.flush.rawValue)] == 4_047_644)
    #expect(counts[Int(HandCategory.fullHouse.rawValue)] == 3_473_184)
    #expect(counts[Int(HandCategory.fourOfAKind.rawValue)] == 224_848)
    #expect(counts[Int(HandCategory.straightFlush.rawValue)] == 41_584)
    #expect(royal == 4_324)
    #expect(rate >= 10_000_000, "evaluator too slow: \(Int(rate)) evals/s")
  }

  @Test func randomSevenCardSpeed() {
    var rng = SeededRNG(seed: 1)
    var hands: [CardSet] = []
    hands.reserveCapacity(1 << 20)
    var deck = Card.all
    for _ in 0..<(1 << 20) {
      for i in 0..<7 { deck.swapAt(i, Int.random(in: i..<52, using: &rng)) }
      hands.append(CardSet(deck[0..<7]))
    }
    var sink = 0
    let clock = ContinuousClock()
    let start = clock.now
    let rounds = 20
    for _ in 0..<rounds {
      for h in hands { sink &+= Int(HandEvaluator.evaluate(h).rawValue) }
    }
    let elapsed = clock.now - start
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let rate = Double(hands.count * rounds) / seconds
    print("Heavy: random 7-card \(Int(rate / 1e6)) M evals/s (sink \(sink))")
    #expect(rate >= 10_000_000, "evaluator too slow: \(Int(rate)) evals/s")
  }

  @Test func randomHandsAgreeWithNaiveInRelease() {
    var rng = SeededRNG(seed: 77)
    var deck = Card.all
    for _ in 0..<300_000 {
      for i in 0..<7 { deck.swapAt(i, Int.random(in: i..<52, using: &rng)) }
      let hand = Array(deck[0..<7])
      if HandEvaluator.evaluate(hand) != NaiveEvaluator.evaluate(hand) {
        Issue.record("mismatch on \(Card.format(hand))")
        return
      }
    }
  }
}
