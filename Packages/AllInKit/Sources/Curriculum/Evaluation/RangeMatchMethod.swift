import Foundation
import PokerAI
import PokerCore
import PokerEquity

/// rangeMatch: paint the hands the actor raises with.
enum RangeMatchMethod {
  static func solve(_ input: EvalInput) throws -> Draft {
    let instance = input.instance
    guard instance.street == .preflop else { throw SpotEvaluationError.invalid("rangeMatch is a preflop method") }
    let actor = instance.actor
    let context = instance.actorContext
    let dead = CardSet(input.heroCards + input.board)
    var weights: [HandClass: Float] = [:]
    let target = input.template.evaluation.target ?? "policy"
    if target == "policy" {
      let strategy = SpotRanges.strategies(instance, characters: input.characters)[actor] ?? BaselineStrategy()
      for handClass in HandClass.all {
        guard let combo = handClass.combos.first(where: { $0.mask.isDisjoint(with: dead) }) else { continue }
        let distribution = strategy.distribution(for: EVOptions.context(context, holding: combo))
        var raise = 0.0
        for entry in distribution.entries where isAggressive(entry.action, legal: context.legal) {
          raise += entry.probability
        }
        weights[handClass] = Float(raise)
      }
    } else {
      let range: HandRange
      do { range = try HandRange(parsing: target) } catch {
        throw SpotEvaluationError.invalid("bad target '\(target)'")
      }
      for handClass in HandClass.all { weights[handClass] = range.weight(of: handClass) }
    }
    let range = HandRange(classWeights: weights)
    var live = 0.0
    var raised = 0.0
    for handClass in HandClass.all {
      let n = Double(handClass.combos.filter { $0.mask.isDisjoint(with: dead) }.count)
      live += n
      raised += n * Double(weights[handClass] ?? 0)
    }
    let share = live > 0 ? raised / live : 0
    let position = instance.positions[actor]?.rawValue ?? "seat"
    var draft = Draft(correct: .range(range), answerClass: position)
    draft.bindings["answer"] = "about \(TextBinder.percent(share)) of hands"
    draft.answerText = "\(input.name(actor)) raises about \(TextBinder.percent(share)) of hands"
    draft.explanation = "From \(position), \(input.name(actor)) raises about \(TextBinder.percent(share)) of hands."
    return draft
  }

  static func isAggressive(_ action: Action, legal: LegalActions) -> Bool {
    switch action {
    case .bet, .raise: true
    case .allIn: !(legal.canCall && legal.callIsAllIn)
    default: false
    }
  }
}
