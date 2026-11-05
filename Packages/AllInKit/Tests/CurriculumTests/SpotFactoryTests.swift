import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

@Suite struct SpotFactoryTests {
  static let library = CurriculumTestSupport.fixture
  static let factory = SpotFactory(library: library, budget: .test)

  /// The attempts the factory makes for `seed`, in order.
  static func attempts(_ id: String, seed: UInt64) async throws -> [(instance: SpotInstance, solution: SpotSolution)] {
    let template = try #require(library.template(id))
    let generator = SpotGenerator(characters: library.characters)
    let evaluator = SpotEvaluator(characters: library.characters, budget: .test)
    var result: [(SpotInstance, SpotSolution)] = []
    for k in 0..<max(1, template.quality.maxRetries + 1) {
      let instance = try generator.generate(template, seed: StableSeed.mix(seed, UInt64(k)))
      result.append((instance, try await evaluator.evaluate(instance, template: template)))
    }
    return result
  }

  @Test func makeProducesABoundPrompt() async throws {
    let spot = try await Self.factory.make(templateID: "fx.ranks.pick-winner", seed: 1)
    #expect(spot.prompt == "Showdown! Who wins the pot?")
    #expect(spot.template.id == "fx.ranks.pick-winner")
    #expect(spot.instance.templateID == spot.template.id)
    #expect(spot.solution.templateID == spot.template.id)
    let named = try await Self.factory.make(templateID: "fx.rules.next-to-act", seed: 2)
    #expect(named.prompt == "The \(named.instance.street.rawValue) is out. Who acts next?")
    #expect(!named.prompt.contains("{"))
  }

  @Test func theSameSeedGivesTheSameSpot() async throws {
    let a = try await Self.factory.make(templateID: "fx.board.what-beats-me", seed: 11)
    let b = try await Self.factory.make(templateID: "fx.board.what-beats-me", seed: 11)
    #expect(a == b)
    let c = try await Self.factory.make(templateID: "fx.board.what-beats-me", seed: 12)
    #expect(a.instance.instanceHash != c.instance.instanceHash)
  }

  @Test func unknownTemplate() async {
    do {
      _ = try await Self.factory.make(templateID: "fx.no.such", seed: 1)
      Issue.record("expected an error")
    } catch SpotFactoryError.unknownTemplate(let id) {
      #expect(id == "fx.no.such")
    } catch {
      Issue.record("wrong error \(error)")
    }
  }

  @Test func targetAnswerClassIsHonouredWithinTheAttempts() async throws {
    // Showdowns come out as category, rank, kicker or split; the factory takes the first attempt that matches.
    var hit = 0
    var fellBack = 0
    for seed in 0..<12 as Range<UInt64> {
      let all = try await Self.attempts("fx.ranks.pick-winner", seed: seed)
      let spot = try await Self.factory.make(
        templateID: "fx.ranks.pick-winner", seed: seed, targetAnswerClass: "category")
      if let first = all.first(where: { $0.solution.answerClass == "category" }) {
        #expect(spot.instance.instanceHash == first.instance.instanceHash)
        #expect(spot.solution.answerClass == "category")
        hit += 1
      } else {
        // No attempt matched: the last one is returned.
        #expect(spot.instance.instanceHash == all.last!.instance.instanceHash)
        fellBack += 1
      }
    }
    print("SPOTFACTORY target category: \(hit) hit, \(fellBack) fell back")
    #expect(hit > 0)
    let rare = try await Self.factory.make(
      templateID: "fx.ranks.pick-winner", seed: 3, targetAnswerClass: "no-such-class")
    let all = try await Self.attempts("fx.ranks.pick-winner", seed: 3)
    #expect(rare.instance.instanceHash == all.last!.instance.instanceHash)
  }

  @Test func retryPicksAGapAboveTheMinimumWhenOneExists() async throws {
    let id = "fx.potodds.obvious"
    let template = try #require(Self.library.template(id))
    let minGap = try #require(template.quality.minGapBB)
    var accepted = 0
    for seed in 0..<3 as Range<UInt64> {
      let all = try await Self.attempts(id, seed: seed)
      let spot = try await Self.factory.make(templateID: id, seed: seed)
      if let first = all.first(where: { ($0.solution.gapBB ?? .infinity) >= minGap }) {
        #expect(spot.instance.instanceHash == first.instance.instanceHash)
        #expect((spot.solution.gapBB ?? .infinity) >= minGap)
        accepted += 1
      } else {
        #expect(spot.instance.instanceHash == all.last!.instance.instanceHash)
      }
    }
    print("SPOTFACTORY min gap \(minGap): \(accepted) of 3 seeds had an attempt above it")
    #expect(accepted > 0)
  }

  @Test func avoidSetKeepsInstancesApart() async throws {
    let first = try await Self.factory.make(templateID: "fx.money.pot-count", seed: 5)
    let second = try await Self.factory.make(
      templateID: "fx.money.pot-count", seed: 5, avoid: [first.instance.instanceHash])
    #expect(second.instance.instanceHash != first.instance.instanceHash)
  }

  @Test func hintOverrideReplacesAndBindsTheHint() async throws {
    let plain = try await Self.factory.make(templateID: "fx.money.pot-count", seed: 9)
    #expect(plain.solution.hint == "Add up everything every player has put in so far.")
    let spot = try await Self.factory.make(
      templateID: "fx.money.pot-count", seed: 9, hintOverride: "It is more than {bigBlind}; start from {potBeforeBet}.")
    #expect(
      spot.solution.hint
        == "It is more than \(spot.instance.config.bigBlind); start from \(spot.solution.bindings["potBeforeBet"]!).")
    #expect(spot.instance == plain.instance)
    do {
      _ = try await Self.factory.make(templateID: "fx.money.pot-count", seed: 9, hintOverride: "{nonsense}")
      Issue.record("expected an error")
    } catch SpotFactoryError.evaluation {
    } catch {
      Issue.record("wrong error \(error)")
    }
  }

  @Test func templateHintIsBoundIntoTheSolution() async throws {
    let spot = try await Self.factory.make(templateID: "fx.potodds.obvious", seed: 2)
    #expect(spot.solution.hint.hasPrefix("You pay \(spot.solution.bindings["toCall"]!) to win"))
    #expect(!spot.solution.hint.contains("{"))
  }
}
