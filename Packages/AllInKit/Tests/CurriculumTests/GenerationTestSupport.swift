import Foundation
import PokerCore

@testable import Curriculum

enum GenerationTestSupport {
  static let generator = SpotGenerator(characters: CurriculumTestSupport.catalog)

  static func template(_ id: String) -> SpotTemplate {
    guard let found = CurriculumTestSupport.fixture.template(id) else { fatalError("no fixture template \(id)") }
    return found
  }

  static var allTemplates: [SpotTemplate] {
    CurriculumTestSupport.fixture.templates.values.sorted { $0.id < $1.id }
  }

  static func cards(_ text: String) -> [Card] {
    do { return try Card.parseList(text) } catch { fatalError("bad cards \(text)") }
  }

  /// A custom template for line tests, based on a heads-up river check-through spot.
  static func custom(
    id: String = "test.custom", players: Int = 2, villains: [VillainSpec] = [], hero: HeroSpec = HeroSpec(),
    line: LineSpec = .checkThrough, street: Street = .river, situation: SituationPredicate? = nil,
    variation: Set<VariationKind> = [], blinds: Blinds = Blinds(small: 1, big: 2)
  ) -> SpotTemplate {
    SpotTemplate(
      id: id, skill: "rules.flow", difficulty: 0.3,
      table: SpotTableSpec(players: players, stacksBB: IntRangeSpec(lo: 60, hi: 100), blinds: blinds),
      hero: hero, villains: villains, line: line, board: BoardPredicate(street: street), situation: situation,
      question: QuestionSpec(type: .choice), evaluation: EvaluationSpec(method: .nextToAct), prompt: "?",
      variation: variation)
  }
}
