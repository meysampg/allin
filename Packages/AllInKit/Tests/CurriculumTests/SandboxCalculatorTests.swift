import Foundation
import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

@Suite struct SandboxCalculatorTests {
  static func state(_ id: String = "fx.potodds.flush-draw", seed: UInt64 = 7) async throws -> SandboxState {
    let b = try await ExplainTestSupport.built(id, seed: seed)
    return SandboxCalculator.initialState(b.instance, villainRanges: b.ranges)
  }

  static func cards(_ text: String) -> [Card] { GenerationTestSupport.cards(text) }

  @Test func initialStateReflectsTheDecision() async throws {
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw")
    let s = SandboxCalculator.initialState(b.instance, villainRanges: b.ranges)
    let context = try #require(b.instance.heroContext)
    #expect(s.heroCards == b.instance.holeCards[b.instance.heroSeat])
    #expect(s.board == b.instance.board)
    #expect(s.villainBet == context.legal.toCall)
    #expect(s.potBeforeBet + s.villainBet == context.pot)
    #expect(s.betRange.contains(s.villainBet))
    #expect(s.betRange.lowerBound == b.instance.config.bigBlind)
    #expect(s.villainName == b.instance.seatNames[b.instance.villainSeats[0]])
    #expect(!SandboxCalculator.dead(s).isEmpty)
  }

  @Test func priceFormula() throws {
    var s = SandboxState(
      heroCards: Self.cards("AhKh"), board: Self.cards("2h7hJc"), potBeforeBet: 100, villainBet: 50,
      betRange: 2...200, bigBlind: 2, villainName: "Bram", villainRange: .full)
    var r = SandboxCalculator.readings(s, meters: [.priceNeeded, .potAfter])
    #expect(abs(try #require(r.priceNeeded) - 0.25) < 1e-12)  // 50 / (100 + 100)
    #expect(r.potAfterCall == 200)
    s.villainBet = 100
    r = SandboxCalculator.readings(s, meters: [.priceNeeded])
    #expect(abs(try #require(r.priceNeeded) - 1.0 / 3.0) < 1e-12)
    #expect(r.potAfterCall == nil)
  }

  @Test func settingACardSwapsADuplicate() {
    let s = SandboxState(
      heroCards: Self.cards("AhKh"), board: Self.cards("2h7hJc"), potBeforeBet: 10, villainBet: 5, betRange: 2...20,
      bigBlind: 2, villainName: "Bram", villainRange: .full)
    let ah = Self.cards("Ah")[0]
    let seven = Self.cards("7h")[0]
    let swapped = SandboxCalculator.setting(.board(1), to: ah, in: s)
    #expect(swapped.board[1] == ah)
    #expect(swapped.heroCards[0] == seven)
    #expect(Set(swapped.heroCards + swapped.board).count == 5)
    let fresh = SandboxCalculator.setting(.hero(0), to: Self.cards("Qs")[0], in: s)
    #expect(fresh.heroCards == Self.cards("QsKh"))
    #expect(fresh.board == s.board)
    #expect(SandboxCalculator.setting(.hero(0), to: ah, in: s) == s)
    #expect(SandboxCalculator.setting(.board(4), to: ah, in: s) == s)
  }

  @Test func readingsForEveryMeter() throws {
    let s = SandboxState(
      heroCards: Self.cards("AhKh"), board: Self.cards("2h7hJc"), potBeforeBet: 100, villainBet: 50, betRange: 2...200,
      bigBlind: 2, villainName: "Bram", villainRange: HandRange.full.removing(CardSet(Self.cards("AhKh2h7hJc"))))
    let r = SandboxCalculator.readings(s, meters: SandboxMeter.allCases)
    #expect(r.priceNeeded != nil)
    #expect(r.potAfterCall == 200)
    #expect(try #require(r.outs).count > 0)
    #expect(r.bestFive?.count == 5)
    #expect(r.bestFiveText?.isEmpty == false)
    #expect(r.nutsText?.isEmpty == false)
    let worse = try #require(r.worseInRange)
    let better = try #require(r.betterInRange)
    #expect(abs(worse + better - 1) < 1e-9)
    #expect(worse > 0 && better > 0)
    // Preflop-ish boards give no hand readings; the river has no outs.
    var river = s
    river.board = Self.cards("2h7hJc3d9s")
    #expect(SandboxCalculator.readings(river, meters: [.outs]).outs == [])
    river.board = []
    let none = SandboxCalculator.readings(river, meters: [.bestFive, .nuts, .worseThatCall])
    #expect(none.bestFive == nil && none.nutsText == nil && none.worseInRange == nil)
  }

  @Test func nutsHandHasNoBetterCallers() {
    // Hero holds the nut flush on a two-tone board vs the full range minus dead cards.
    let hero = Self.cards("AhKh")
    let board = Self.cards("2h7hJh")
    let s = SandboxState(
      heroCards: hero, board: board, potBeforeBet: 10, villainBet: 5, betRange: 2...20, bigBlind: 2,
      villainName: "Bram", villainRange: .full)
    let r = SandboxCalculator.readings(s, meters: [.worseThatCall, .betterThatCall])
    #expect(r.betterInRange == 0)
    #expect(r.worseInRange == 1)
  }

  @Test func chanceFirstEstimateHasTwoThousandSamples() async throws {
    let s = try await Self.state()
    let clock = ContinuousClock()
    let start = clock.now
    var first: EquityEstimate?
    var count = 0
    for await estimate in SandboxCalculator.chance(s, seed: 99, totalSamples: 6000) {
      if first == nil {
        first = estimate
        print("SANDBOX first-estimate latency \(clock.now - start)")
      }
      count += 1
      if estimate.isFinal { #expect(estimate.samples == 6000) }
    }
    let estimate = try #require(first)
    #expect(estimate.samples == 2000)
    #expect(count == 3)
    #expect((0.0...1.0).contains(try #require(estimate.results.first).equity))
  }

  @Test func chanceIsDeterministicAndCancelSafe() async throws {
    let s = try await Self.state()
    var a: [EquityEstimate] = []
    for await e in SandboxCalculator.chance(s, seed: 5, totalSamples: 4000) { a.append(e) }
    var b: [EquityEstimate] = []
    for await e in SandboxCalculator.chance(s, seed: 5, totalSamples: 4000) { b.append(e) }
    #expect(a == b)
    // Stop after the first estimate.
    for await _ in SandboxCalculator.chance(s, seed: 5, totalSamples: 1_000_000) { break }
  }

  @Test func chanceTracksTheHand() async throws {
    var s = try await Self.state()
    s.heroCards = Self.cards("AhAd")
    s.board = Self.cards("As7c2d")
    s.villainRange = HandRange.full.removing(SandboxCalculator.dead(s))
    var last: EquityEstimate?
    for await e in SandboxCalculator.chance(s, seed: 1, totalSamples: 2000) { last = e }
    #expect(try #require(last?.results.first).equity > 0.9)
  }
}
