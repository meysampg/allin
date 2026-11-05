import Foundation
import PokerAI
import PokerAnalysis
import PokerCore
import PokerEquity

/// pushFold: heads-up preflop shove or fold against the villain's calling range.
enum PushFoldMethod {
  /// - Parameter strategy: replaces the villain's own strategy (tests).
  static func solve(
    _ input: EvalInput, ranges: [Int: HandRange], strategy override: (any StrategyProvider)? = nil
  ) throws -> Draft {
    let context = try input.heroContext()
    guard context.street == .preflop else { throw SpotEvaluationError.invalid("pushFold is a preflop method") }
    let villain = try input.soleVillain(context)
    let strategy =
      override ?? SpotRanges.strategies(input.instance, characters: input.characters)[villain] ?? BaselineStrategy()
    let options = try EVOptions.resolve(input.template.question.options ?? ["fold", "allin"], context: context)
    let legal = context.legal
    guard legal.canAllIn, let villainView = context.view(of: villain) else {
      throw SpotEvaluationError.optionUnavailable("allin")
    }
    let dead = CardSet(input.heroCards)
    var range = (ranges[villain] ?? .full).removing(dead)
    if range.totalWeight <= 0 { range = HandRange.full.removing(dead) }

    let step: HandStep
    do { step = try HandReducer.apply(.allIn, to: input.instance.state) } catch {
      throw SpotEvaluationError.optionUnavailable("allin")
    }
    let history = input.instance.history + EVOptions.entry(of: step.records, street: .preflop)
    let reply = DecisionContext.make(from: step.state, for: villain, history: history)

    let heroCommitted = legal.committed
    let villainCommitted = villainView.committedThisStreet
    let x = max(0, min(legal.stack, villainView.stack + villainCommitted - heroCommitted))
    let finalPot = context.pot + x + (x + heroCommitted - villainCommitted)
    let pot = Double(context.pot)

    var weightSum = 0.0
    var evSum = 0.0
    var callWeight = 0.0
    var callEquity = 0.0
    for combo in range.nonZeroCombos {
      let w = Double(range[combo])
      let pCall: Double
      if let reply {
        let held = EVOptions.context(reply, holding: combo)
        let distribution = strategy.distribution(for: held)
        pCall =
          distribution.probability(of: .call) + (held.legal.callIsAllIn ? distribution.probability(of: .allIn) : 0)
      } else {
        pCall = 1
      }
      let eq = pCall > 0 ? EquityCalculator.preflop(input.heroCards, combo.cards).equity : 0
      weightSum += w
      evSum += w * ((1 - pCall) * pot + pCall * (eq * Double(finalPot) - Double(x)))
      callWeight += w * pCall
      callEquity += w * pCall * eq
    }
    let allInChips = weightSum > 0 ? evSum / weightSum : 0
    let bb = Double(input.bigBlind)
    var candidates: [CandidateEV] = []
    for option in options {
      let isAllIn = option.action == .allIn
      candidates.append(
        CandidateEV(
          action: option.action, label: ActionLabel.long(option.action, context: context),
          shortLabel: ActionLabel.short(option.action, context: context), evBB: isAllIn ? allInChips / bb : 0,
          standardError: 0, samples: 0, method: isAllIn ? .closedForm : .exactFold))
    }
    var draft = try EVOptions.draft(context: context, options: options, candidates: candidates)
    draft.bindings["priceNeeded"] = TextBinder.percent(finalPot > 0 ? Double(x) / Double(finalPot) : 0)
    draft.bindings["equity"] = TextBinder.percent(callWeight > 0 ? callEquity / callWeight : 0)
    draft.villainRanges = [villain: range]
    return draft
  }
}
