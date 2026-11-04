import PokerCore
import PokerEquity
import PokerHost
import Testing

@testable import PokerAI

@Suite struct PersonalityParamsTests {
  private func grumli() throws -> PersonalityParams {
    try #require(AITestSupport.personalities().first { $0.id == "grumli" }?.strategy.params)
  }

  @Test func variedIsDeterministicAndInRange() throws {
    let base = try grumli()
    let variation = ["vpip": 0.3, "stickiness": 0.5, "bluffFreq": 0.2, "readSkill": 0.4]
    for seed in 0..<50 as Range<UInt64> {
      let a = base.varied(by: variation, seed: seed)
      #expect(a == base.varied(by: variation, seed: seed))
      try a.validate()
      #expect(abs(a.vpip - base.vpip) <= 0.3 + 1e-12)
      #expect(a.bluffFreq >= 0 && a.bluffFreq <= 1)
      #expect(a.threeBet == base.threeBet)  // unnamed fields stay
    }
    #expect(base.varied(by: variation, seed: 1) != base.varied(by: variation, seed: 2))
  }

  @Test func variedClampsToTheValidRange() throws {
    var base = try grumli()
    base.stickiness = 0.99
    for seed in 0..<30 as Range<UInt64> {
      let a = base.varied(by: ["stickiness": 0.9, "continueThreshold": 5], seed: seed)
      try a.validate()
      #expect(a.stickiness <= 1)
    }
  }

  @Test func validateRejectsOutOfRange() throws {
    var p = try grumli()
    try p.validate()
    p.slowplay = -0.1
    #expect(throws: PersonalityParamsError.self) { try p.validate() }
    p = try grumli()
    p.valueThreshold = 0
    #expect(throws: PersonalityParamsError.self) { try p.validate() }
    p = try grumli()
    p.sizing.bluff = -1
    #expect(throws: PersonalityParamsError.self) { try p.validate() }
    p = try grumli()
    p.sizing.overbetFrequency = 2
    #expect(throws: PersonalityParamsError.self) { try p.validate() }
  }
}

@Suite struct PersonalityTests {
  private let bots: [(id: String, strategy: PersonalityStrategy)]

  init() throws { bots = try AITestSupport.personalities() }

  private func bot(_ id: String) -> PersonalityStrategy { bots.first { $0.id == id }!.strategy }

  @Test(arguments: AITestSupport.characterIDs)
  func distributionsAreValidForRandomContexts(id: String) throws {
    let strategy = try AITestSupport.bot(id)
    var decisions = 0
    for index in 0..<300 {
      try AIRandomPlayout.decisions(index: index, baseSeed: 0xB07) { context in
        let distribution = strategy.distribution(for: context)
        do { try distribution.validate(against: context.legal) } catch {
          Issue.record("\(id): \(error) at hand \(index), \(context.street), legal \(context.legal)")
        }
        for entry in distribution.entries {
          #expect(entry.probability > 0 && entry.probability <= 1 + 1e-12)
        }
        decisions += 1
      }
    }
    #expect(decisions > 600)
  }

  @Test(arguments: AITestSupport.characterIDs)
  func distributionsArePure(id: String) throws {
    let strategy = try AITestSupport.bot(id)
    for index in 0..<15 {
      try AIRandomPlayout.decisions(index: index, baseSeed: 0xB08) { context in
        #expect(strategy.distribution(for: context) == strategy.distribution(for: context))
      }
    }
  }

  @Test func equalParamsAndSeedAgree() {
    let params = bot("zib").params
    let context = AIScript.context(actions: [.fold, .fold], hole: "Ah Kd")
    #expect(
      PersonalityStrategy(params: params, seed: 3).distribution(for: context)
        == PersonalityStrategy(params: params, seed: 3).distribution(for: context))
  }

  /// Share of the 1326 combos the strategy plays (not fold, not check) in an unopened 6-max pot, averaged over
  /// the positions that can be unopened.
  private func unopenedPlayFraction(_ strategy: PersonalityStrategy) -> Double {
    // Seats 3, 4, 5, 0, 1 are UTG, HJ, CO, BTN, SB (button 0).
    var total = 0.0
    let folds: [[Action]] = [[], [.fold], [.fold, .fold], [.fold, .fold, .fold], [.fold, .fold, .fold, .fold]]
    for actions in folds {
      let base = AIScript.context(actions: actions)
      var played = 0.0
      for combo in Combo.all {
        let context = AIScript.withHole(base, combo.cards)
        played += AIScript.playing(strategy.distribution(for: context))
      }
      total += played / Double(Combo.all.count)
    }
    return total / Double(folds.count)
  }

  @Test func unopenedPlayFractionMatchesTheCharacter() {
    #expect(abs(unopenedPlayFraction(bot("grumli")) - 0.55) <= 0.07)
    #expect(abs(unopenedPlayFraction(bot("vexa")) - 0.14) <= 0.03)
  }

  @Test func looserCharactersPlayMore() {
    let mott = unopenedPlayFraction(bot("mott"))
    let vexa = unopenedPlayFraction(bot("vexa"))
    let bram = unopenedPlayFraction(bot("bram"))
    let zib = unopenedPlayFraction(bot("zib"))
    #expect(mott < vexa)
    #expect(vexa < bram)
    #expect(bram < zib)
  }

  @Test func aggressionIsMonotoneInHandStrength() {
    let situations: [(String, [Action])] = [
      ("unopened", [.fold, .fold, .fold]),
      ("limped", [.call, .fold, .fold]),
      ("facingOpen", [.raise(to: 250), .fold, .fold]),
      ("facingThreeBet", [.raise(to: 250), .fold, .fold, .fold, .raise(to: 900), .fold]),
      ("facingFourBet", [.raise(to: 250), .fold, .fold, .fold, .raise(to: 900), .fold, .raise(to: 2000)]),
    ]
    for (name, actions) in situations {
      let base = AIScript.context(actions: actions)
      for (id, strategy) in bots {
        let aces = AIScript.aggression(
          strategy.distribution(for: AIScript.withHole(base, AITestSupport.cards("As Ah"))))
        let trash = AIScript.aggression(
          strategy.distribution(for: AIScript.withHole(base, AITestSupport.cards("7s 2h"))))
        #expect(aces > trash, "\(id) \(name): AA \(aces) vs 72o \(trash)")
      }
    }
  }

  @Test func stationCallsMoreThanTheRockWithBottomPairOnTheRiver() {
    // Heads-up, limped pot checked down to the river, then the opponent bets half the pot.
    let actions: [Action] = [.call, .check, .check, .check, .check, .check, .check, .bet(to: 100)]
    let context = AIScript.context(seats: 2, actions: actions, hole: "2d 7c", board: "Ks 9d 6c 4h 2s")
    #expect(context.legal.toCall == 100)
    let station = bot("grumli").distribution(for: context)
    let rock = bot("vexa").distribution(for: context)
    let stationCalls = station.probability(of: .call)
    let rockCalls = rock.probability(of: .call)
    #expect(stationCalls > rockCalls, "grumli \(stationCalls) vexa \(rockCalls)")
  }

  @Test func shortStacksNeverProduceIllegalActions() {
    for stack in [30, 100, 150, 600] {
      for actions in [[Action](), [.raise(to: 300)], [.allIn], [.call, .check]] {
        guard let context = AIScript.optionalContext(seats: 3, actions: actions, hole: "Ah Kd", stack: stack) else {
          continue
        }
        for (id, strategy) in bots {
          do { try strategy.distribution(for: context).validate(against: context.legal) } catch {
            Issue.record("\(id) stack \(stack): \(error)")
          }
        }
      }
    }
  }

  @Test(arguments: AITestSupport.characterIDs)
  func beatsRandomHeadsUp(id: String) throws {
    let strategy = try AITestSupport.bot(id)
    let random = Contestant(name: "random", strategy: UniformRandomStrategy())
    // Few deals keep the debug run fast and the result is noisy for the tight bots, so the seed is fixed; the
    // statistically meaningful gate (thousands of deals) is the release-mode simulation suite.
    let config = MatchConfig.headsUp(deals: 40, seed: 1)
    let report = HeadlessMatch.headsUpDuplicate(Contestant(name: id, strategy: strategy), random, config: config)
    #expect(report.aWinRate.bbPer100 > 0, "\(id): \(report.aWinRate.bbPer100) bb/100")
  }
}
