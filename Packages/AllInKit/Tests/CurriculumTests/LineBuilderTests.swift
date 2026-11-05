import PokerCore
import Testing

@testable import Curriculum

@Suite struct LineBuilderTests {
  static let generator = GenerationTestSupport.generator

  static func tokens(_ texts: String...) -> [LineToken] {
    texts.map { try! LineToken(parsing: $0) }
  }

  /// Hero BB against vexa on the button: open 2.5, call, check, bet.
  static func betLine(consistent: Bool, bet: String = "0.5-0.75") -> SpotTemplate {
    GenerationTestSupport.custom(
      id: "test.betline", villains: [VillainSpec(characters: ["vexa"], position: [.btn])],
      hero: HeroSpec(position: [.bb]),
      line: LineSpec(
        streets: [
          .preflop: tokens("villain:open:2.5", "hero:call"), .flop: tokens("hero:check", "villain:bet:\(bet)"),
        ], stopAt: .hero, consistent: consistent),
      street: .flop, blinds: Blinds(small: 5, big: 10))
  }

  @Test func checkThroughReachesRiverWithNoBets() throws {
    let template = GenerationTestSupport.custom(variation: [.seats])
    for seed in 0..<40 {
      let instance = try Self.generator.generate(template, seed: UInt64(seed))
      #expect(instance.street == .river)
      #expect(instance.actor == instance.heroSeat)
      #expect(instance.state.legalActions?.toCall == 0)
      #expect(instance.actions.allSatisfy { $0 == .check || $0 == .call })
      #expect(instance.board.count == 5)
    }
  }

  @Test func openCallThenFlopBetFacesABetInsideTheRange() throws {
    let template = Self.betLine(consistent: false)
    for seed in 0..<40 {
      let instance = try Self.generator.generate(template, seed: UInt64(seed))
      let legal = try #require(instance.state.legalActions)
      #expect(instance.street == .flop)
      #expect(legal.toCall > 0)
      let pot = instance.state.pot
      let fraction = Double(legal.toCall) / Double(pot - legal.toCall)
      #expect(fraction >= 0.5 - 0.06 && fraction <= 0.75 + 0.06, "bet fraction \(fraction)")
      #expect(instance.positions[instance.heroSeat] == .bb)
      #expect(instance.positions[instance.villainSeats[0]] == .btn)
      // Open to 2.5bb, call, check, bet.
      #expect(instance.actions.count == 4)
      #expect(instance.actions[0] == .raise(to: 25))
      #expect(instance.actions[1] == .call)
      #expect(instance.actions[2] == .check)
    }
  }

  @Test func uninvolvedSeatsFold() throws {
    let template = GenerationTestSupport.custom(
      players: 6, villains: [VillainSpec(position: [.co])], hero: HeroSpec(position: [.btn]),
      line: LineSpec(stopAt: .villain), street: .preflop)
    for seed in 0..<20 {
      let instance = try Self.generator.generate(template, seed: UInt64(seed))
      // UTG and HJ act before the cutoff.
      #expect(instance.actions == [.fold, .fold])
      #expect(instance.positions[instance.actor] == .co)
      #expect(instance.villainSeats == [instance.actor])
    }
  }

  @Test func consistencyRejectsSomeBetsAgainstBram() {
    let template = GenerationTestSupport.custom(
      id: "test.bram", villains: [VillainSpec(characters: ["bram"], position: [.btn])],
      hero: HeroSpec(position: [.bb]),
      line: LineSpec(
        streets: [
          .preflop: Self.tokens("villain:open:2.5", "hero:call"),
          .flop: Self.tokens("hero:check", "villain:bet:0.5-0.75"),
        ],
        stopAt: .hero, consistent: true),
      street: .flop, blinds: Blinds(small: 5, big: 10))
    var consistency = 0
    var built = 0
    for attempt in 0..<80 {
      switch Self.generator.attempt(template, seed: 21, attempt: attempt) {
      case .success: built += 1
      case .failure(let reject): if reject.reason == "consistency" { consistency += 1 }
      }
    }
    print("LINEBUILDER bram bet line: \(built) built, \(consistency) consistency rejections of 80")
    #expect(consistency > 0)
  }

  @Test func inconsistentLinesAreNeverRejectedForConsistency() {
    let template = Self.betLine(consistent: false)
    for attempt in 0..<40 {
      if case .failure(let reject) = Self.generator.attempt(template, seed: 22, attempt: attempt) {
        #expect(reject.reason != "consistency")
      }
    }
  }

  @Test func randomModeStopsAtTheHero() throws {
    let template = GenerationTestSupport.custom(
      players: 3, line: LineSpec(random: RandomLineSpec(actions: IntRangeSpec(lo: 2, hi: 4)), stopAt: .hero),
      street: .flop, variation: [.seats])
    for seed in 0..<40 {
      let instance = try Self.generator.generate(template, seed: UInt64(seed))
      #expect(instance.actor == instance.heroSeat)
      #expect(instance.street == .flop)
      #expect(instance.actions.count >= 2)
      #expect(instance.villainSeats.count == 2)
    }
  }

  @Test func randomModeStopsAtAnyActor() throws {
    let template = GenerationTestSupport.custom(
      players: 6, line: LineSpec(random: RandomLineSpec(actions: IntRangeSpec(lo: 1, hi: 9)), stopAt: .any),
      street: .flop, variation: [.seats])
    for seed in 0..<40 {
      let instance = try Self.generator.generate(template, seed: UInt64(seed))
      #expect(instance.street == .flop)
      #expect(instance.state.seatToAct != nil)
    }
  }

  @Test func illegalTokenRejectsTheLine() {
    // "check" is never legal facing the big blind preflop for the button.
    let template = GenerationTestSupport.custom(
      villains: [VillainSpec(position: [.btn])], hero: HeroSpec(position: [.bb]),
      line: LineSpec(streets: [.preflop: Self.tokens("villain:check")], stopAt: .hero), street: .preflop)
    guard case .failure(let reject) = Self.generator.attempt(template, seed: 1, attempt: 0) else {
      Issue.record("expected a rejection")
      return
    }
    #expect(reject.reason == "line")
  }

  @Test func exhaustionReportsReasons() {
    let template = GenerationTestSupport.custom(
      villains: [VillainSpec(position: [.btn])], hero: HeroSpec(position: [.bb]),
      line: LineSpec(streets: [.preflop: Self.tokens("villain:check")], stopAt: .hero), street: .preflop)
    #expect(throws: SpotGenerationError.self) { try Self.generator.generate(template, seed: 1) }
    do { _ = try Self.generator.generate(template, seed: 1) } catch let error as SpotGenerationError {
      #expect("\(error)".contains("could not build test.custom in 2000 tries (line 2000)"))
    } catch {}
  }

  @Test func avoidExcludesAHash() throws {
    let template = GenerationTestSupport.template("fx.ranks.pick-winner")
    let first = try Self.generator.generate(template, seed: 4)
    let second = try Self.generator.generate(template, seed: 4, avoid: [first.instanceHash])
    #expect(second.instanceHash != first.instanceHash)
    #expect(second.attempt > first.attempt)
  }

  @Test func deterministicPerSeed() throws {
    let template = GenerationTestSupport.template("fx.rules.call-cost")
    let a = try Self.generator.generate(template, seed: 99)
    let b = try Self.generator.generate(template, seed: 99)
    #expect(a == b)
    let c = try Self.generator.generate(template, seed: 100)
    #expect(a.instanceHash != c.instanceHash)
  }

  @Test func invalidTemplatesThrow() {
    let tooMany = GenerationTestSupport.custom(villains: [VillainSpec(), VillainSpec()])
    #expect(throws: SpotGenerationError.invalidTemplate("2 villains at a 2-player table")) {
      try Self.generator.generate(tooMany, seed: 1)
    }
  }
}
