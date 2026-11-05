import Foundation
import PokerAnalysis
import PokerCore
import PokerEquity

/// An action option of an EV question, resolved against the decision.
struct ResolvedOption: Sendable, Hashable {
  /// "fold", "call", "bet:0.5", "raise:3", "allin".
  let token: String
  /// In the canonical form of `ActionEVResult.candidates`.
  let action: Action

  /// fold | check | call | bet | raise | allin.
  var answerClass: String { String(token.split(separator: ":")[0]) }
}

enum EVOptions {
  /// Option tokens to actions. bet:F is a pot-sized bet or raise (F of the pot after calling); raise:X is a raise to
  /// X times the current bet (X big blinds when nobody has bet). Options that snap to the same action are dropped.
  static func resolve(_ tokens: [String], context: DecisionContext) throws -> [ResolvedOption] {
    let legal = context.legal
    var result: [ResolvedOption] = []
    var seen = Set<Action>()
    for token in tokens {
      let parts = token.split(separator: ":", omittingEmptySubsequences: false)
      let action: Action?
      switch parts[0] {
      case "fold": action = .fold
      case "check": action = legal.canCheck ? .check : nil
      case "call": action = legal.canCall ? .call : nil
      case "allin": action = legal.canAllIn ? .allIn : nil
      case "bet":
        let fraction = parts.count == 2 ? Double(parts[1]) : nil
        action = fraction.flatMap {
          ActionDistribution.potSizedRaises(fractions: [$0], pot: context.pot, legal: legal).first
        }
      case "raise":
        let multiple = parts.count == 2 ? Double(parts[1]) : nil
        let base = legal.currentBet > 0 ? legal.currentBet : context.config.bigBlind
        action = multiple.flatMap { ActionDistribution.snapRaise(to: Int((Double(base) * $0).rounded()), legal: legal) }
      default: action = nil
      }
      guard let action else { throw SpotEvaluationError.optionUnavailable(token) }
      let canonical = DecisionGrader.canonical(action, legal: legal)
      if seen.insert(canonical).inserted { result.append(ResolvedOption(token: token, action: canonical)) }
    }
    return result
  }

  /// The draft of an EV spot from candidates in option order.
  static func draft(
    context: DecisionContext, options: [ResolvedOption], candidates: [CandidateEV]
  ) throws -> Draft {
    guard !candidates.isEmpty, candidates.count == options.count else {
      throw SpotEvaluationError.invalid("no candidates")
    }
    let evs = ActionEVResult(candidates: candidates)
    let best = evs.best
    let bestIndex = candidates.firstIndex { $0.action == best.action } ?? 0
    let ranked = evs.ranked
    let gap = ranked.count > 1 ? best.evBB - ranked[1].evBB : nil
    var draft = Draft(correct: .option(options[bestIndex].token), answerClass: options[bestIndex].answerClass)
    draft.options = zip(options, candidates).map { AnswerOption(id: $0.token, label: $1.label, evBB: $1.evBB) }
    draft.evs = evs
    draft.gapBB = gap
    draft.potBefore = context.pot
    draft.bindings["evGain"] = TextBinder.bb(best.evBB, signed: true)
    draft.bindings["bestAction"] = best.shortLabel
    draft.bindings["answer"] = best.label
    draft.answerText = "\(best.label) is best"
    draft.explanation = "\(best.label) averages \(TextBinder.bb(best.evBB, signed: true))."
    return draft
  }

  /// A history entry for the hero's action just applied.
  static func entry(of records: [HandRecord], street: Street) -> [ActionEntry] {
    records.compactMap { record in
      guard case .actionApplied(let a, _) = record else { return nil }
      return ActionEntry(
        street: street, seat: a.seat, action: a.action, chipsAdded: a.chipsAdded, committedAfter: a.committedAfter,
        isAllIn: a.isAllIn)
    }
  }

  /// `context` as seen with other hole cards.
  static func context(_ context: DecisionContext, holding combo: Combo) -> DecisionContext {
    DecisionContext(
      config: context.config, seat: context.seat, holeCards: combo.cards, board: context.board,
      street: context.street, button: context.button, smallBlindSeat: context.smallBlindSeat,
      bigBlindSeat: context.bigBlindSeat, seats: context.seats, pot: context.pot, history: context.history,
      legal: context.legal)
  }

  /// Hero equity against a range: exact on the river, else seeded Monte Carlo.
  static func equity(hero: [Card], range: HandRange, board: [Card], samples: Int, seed: UInt64) -> EquityResult {
    if board.count == 5 { return EquityCalculator.exact(hero: hero, vs: range, board: board) }
    var rng = SeededRNG(seed: seed)
    return EquityCalculator.monteCarlo(hero: hero, vs: [range], board: board, samples: max(samples, 1), using: &rng)
  }
}
