import PokerCore
import PokerEquity

/// How an action is grouped when the exact action has zero probability for every combo.
enum ActionClass: Sendable, Hashable {
  case fold
  case checkCall
  case aggressive

  static func of(_ action: Action, legal: LegalActions) -> ActionClass {
    switch action {
    case .fold: return .fold
    case .check, .call: return .checkCall
    case .bet, .raise: return .aggressive
    case .allIn: return legal.canCall && legal.callIsAllIn ? .checkCall : .aggressive
    }
  }
}

enum Likelihood {
  /// The context as seen for a hypothetical hand: only the hole cards change.
  static func context(_ context: DecisionContext, holding combo: Combo) -> DecisionContext {
    DecisionContext(
      config: context.config, seat: context.seat, holeCards: combo.cards, board: context.board,
      street: context.street, button: context.button, smallBlindSeat: context.smallBlindSeat,
      bigBlindSeat: context.bigBlindSeat, seats: context.seats, pot: context.pot, history: context.history,
      legal: context.legal)
  }

  /// P(action | combo): exact action, or (fallback) the summed probability of the action's class.
  static func probability(
    of action: Action, byClass: Bool, combo: Combo, context: DecisionContext, strategy: any StrategyProvider
  ) -> Double {
    let distribution = strategy.distribution(for: Likelihood.context(context, holding: combo))
    guard byClass else { return distribution.probability(of: action) }
    let target = ActionClass.of(action, legal: context.legal)
    var total = 0.0
    for entry in distribution.entries where ActionClass.of(entry.action, legal: context.legal) == target {
      total += entry.probability
    }
    return total
  }
}
