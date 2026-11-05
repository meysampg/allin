import Foundation
import PokerAI
import PokerCore
import PokerEquity

@testable import Curriculum

enum EvaluationTestSupport {
  static let catalog = CurriculumTestSupport.catalog
  static let generator = GenerationTestSupport.generator
  static let evaluator = SpotEvaluator(characters: CurriculumTestSupport.catalog, budget: .test)

  static func cards(_ text: String) -> [Card] { GenerationTestSupport.cards(text) }

  static func template(_ id: String) -> SpotTemplate { GenerationTestSupport.template(id) }

  /// The fixture template with its evaluation, question or quality replaced.
  static func variant(
    _ base: SpotTemplate, evaluation: EvaluationSpec? = nil, question: QuestionSpec? = nil,
    fixed: FixedCards? = nil, line: LineSpec? = nil, hint: String? = nil, board: BoardPredicate? = nil
  ) -> SpotTemplate {
    SpotTemplate(
      id: base.id, skill: base.skill, difficulty: base.difficulty, table: base.table, hero: base.hero,
      villains: base.villains, fixed: fixed ?? base.fixed, line: line ?? base.line, board: board ?? base.board,
      situation: base.situation, potBB: base.potBB, question: question ?? base.question,
      evaluation: evaluation ?? base.evaluation, quality: base.quality, prompt: base.prompt, coach: base.coach,
      hint: hint ?? base.hint, explain: base.explain, variation: base.variation, reveal: base.reveal)
  }

  /// A heads-up or multiway spot with every card fixed and the hand checked through to `street`.
  static func fixedSpot(
    method: EvaluationMethod, question: QuestionSpec, street: Street, hero: String, board: String,
    villains: [String] = ["QcJd"], players: Int? = nil, ask: LegalAsk? = nil,
    buckets: [CountBucket]? = nil, line: LineSpec = .checkThrough, hint: String? = nil,
    heroPosition: SeatPositionName? = nil, villainPosition: SeatPositionName? = nil
  ) -> (template: SpotTemplate, instance: SpotInstance) {
    let template = SpotTemplate(
      id: "test.eval", skill: "rules.flow", difficulty: 0.3,
      table: SpotTableSpec(
        players: players ?? (villains.count + 1), stacksBB: IntRangeSpec(lo: 100, hi: 100),
        blinds: Blinds(small: 1, big: 2)),
      hero: HeroSpec(position: heroPosition.map { [$0] }),
      villains: villains.map { _ in VillainSpec(position: villainPosition.map { [$0] }) },
      fixed: FixedCards(hero: cards(hero), villains: villains.map(cards), board: cards(board)), line: line,
      board: BoardPredicate(street: street), question: question,
      evaluation: EvaluationSpec(method: method, ask: ask, buckets: buckets), prompt: "?", hint: hint)
    do {
      return (template, try generator.generate(template, seed: 1))
    } catch {
      fatalError("cannot build the test spot: \(error)")
    }
  }

  /// A line written as content JSON.
  static func line(_ json: String) -> LineSpec {
    do { return try JSONDecoder().decode(LineSpec.self, from: Data(json.utf8)) } catch {
      fatalError("bad line \(json)")
    }
  }

  /// Heads-up: the villain opens to 2.5 bb from the button, the hero calls in the big blind, and the villain bets
  /// half the pot on the flop. Pot 15 (chips, blinds 1/2), the hero to act facing 5.
  static let facingFlopBet = line(
    #"{"preflop":["villain:open:2.5","hero:call"],"flop":["hero:check","villain:bet:0.5"]}"#)

  static func solve(_ spot: (template: SpotTemplate, instance: SpotInstance)) throws -> SpotSolution {
    try evaluator.evaluateSerial(spot.instance, template: spot.template)
  }

  /// Calls (or checks) with certainty.
  struct AlwaysCall: StrategyProvider {
    func distribution(for context: DecisionContext) -> ActionDistribution {
      try! ActionDistribution(certain: context.legal.canCheck ? .check : .call, legal: context.legal)
    }
  }

  struct AlwaysFold: StrategyProvider {
    func distribution(for context: DecisionContext) -> ActionDistribution {
      try! ActionDistribution(certain: context.legal.toCall > 0 ? .fold : .check, legal: context.legal)
    }
  }
}
