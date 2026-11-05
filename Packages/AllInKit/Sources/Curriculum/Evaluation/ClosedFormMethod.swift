import Foundation
import PokerAI
import PokerAnalysis
import PokerCore
import PokerEquity

/// closedFormEV: chip formulas over the hero's equity against the villain's range.
enum ClosedFormMethod {
  static func solve(_ input: EvalInput, ranges: [Int: HandRange]) throws -> Draft {
    let context = try input.heroContext()
    let villain = try input.soleVillain(context)
    let strategy = SpotRanges.strategies(input.instance, characters: input.characters)[villain] ?? BaselineStrategy()
    let dead = CardSet(input.heroCards + input.board)
    var range: HandRange
    if let text = input.template.evaluation.vsRange, text != "tracked" {
      do { range = try HandRange(parsing: text) } catch { throw SpotEvaluationError.invalid("bad vsRange '\(text)'") }
    } else {
      range = ranges[villain] ?? .full
    }
    range = range.removing(dead)
    if range.totalWeight <= 0 { range = HandRange.full.removing(dead) }
    let tokens = input.template.question.options ?? []
    let options = try EVOptions.resolve(tokens, context: context)
    let samples = input.template.evaluation.equitySamples ?? input.budget.equitySamples
    let seed = input.instance.seed
    let equity = EVOptions.equity(
      hero: input.heroCards, range: range, board: input.board, samples: samples, seed: StableSeed.mix(seed, 0xE0))
    let bb = Double(input.bigBlind)
    var candidates: [CandidateEV] = []
    for (index, option) in options.enumerated() {
      let chips = try value(
        of: option.action, input: input, context: context, villain: villain, strategy: strategy, range: range,
        equity: equity.equity, samples: samples, seed: StableSeed.mix(seed, 0xE1 + UInt64(index)))
      candidates.append(
        CandidateEV(
          action: option.action, label: ActionLabel.long(option.action, context: context),
          shortLabel: ActionLabel.short(option.action, context: context), evBB: chips / bb, standardError: 0,
          samples: option.action == .fold ? 0 : equity.samples,
          method: option.action == .fold ? .exactFold : .closedForm))
    }
    var draft = try EVOptions.draft(context: context, options: options, candidates: candidates)
    draft.bindings["priceNeeded"] = TextBinder.percent(context.potOdds)
    draft.bindings["equity"] = TextBinder.percent(equity.equity)
    draft.villainRanges = [villain: range]
    return draft
  }

  /// The value in chips of `action` for the hero.
  static func value(
    of action: Action, input: EvalInput, context: DecisionContext, villain: Int, strategy: any StrategyProvider,
    range: HandRange, equity: Double, samples: Int, seed: UInt64
  ) throws -> Double {
    let legal = context.legal
    switch action {
    case .fold: return 0
    case .check: return equity * Double(context.pot)
    case .call: return ClosedFormEV.call(equity: equity, pot: context.pot, toCall: legal.callAmount)
    case .allIn where legal.callIsAllIn && legal.canCall:
      return ClosedFormEV.call(equity: equity, pot: context.pot, toCall: legal.callAmount)
    case .bet, .raise, .allIn:
      let step: HandStep
      do { step = try HandReducer.apply(action, to: input.instance.state) } catch {
        throw SpotEvaluationError.optionUnavailable("\(action)")
      }
      let added = EVOptions.entry(of: step.records, street: input.instance.street)
      let heroAdded = added.first?.chipsAdded ?? 0
      guard
        let reply = DecisionContext.make(
          from: step.state, for: villain, history: input.instance.history + added)
      else {
        // The villain cannot answer (all-in already): nobody folds and the hand runs out.
        return equityValue(equity, pot: context.pot, bet: heroAdded, call: 0)
      }
      var foldWeight = 0.0
      var totalWeight = 0.0
      var calledWeights = [Float](repeating: 0, count: Combo.count)
      for combo in range.nonZeroCombos {
        let w = Double(range[combo])
        let pFold = RangeTracker.likelihood(of: .fold, combo: combo, context: reply, strategy: strategy)
        totalWeight += w
        foldWeight += w * pFold
        calledWeights[combo.index] = Float(w * (1 - pFold))
      }
      guard totalWeight > 0 else { return equityValue(equity, pot: context.pot, bet: heroAdded, call: 0) }
      let foldEquity = foldWeight / totalWeight
      let called = HandRange(weights: calledWeights)
      let eqCalled =
        called.totalWeight > 0
        ? EVOptions.equity(hero: input.heroCards, range: called, board: input.board, samples: samples, seed: seed)
          .equity
        : 0
      let call = reply.legal.callAmount
      // Chips the villain cannot match come back to the hero.
      let effectiveBet = heroAdded - max(0, reply.legal.toCall - reply.legal.stack)
      return ClosedFormEV.bet(
        foldEquity: foldEquity, equityWhenCalled: eqCalled, pot: context.pot, bet: effectiveBet, call: call)
    }
  }

  private static func equityValue(_ equity: Double, pot: Int, bet: Int, call: Int) -> Double {
    equity * Double(pot + bet + call) - Double(bet)
  }
}
