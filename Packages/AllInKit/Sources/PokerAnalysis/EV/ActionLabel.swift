import PokerCore

/// Human-readable action names for the coach and chart axes.
public enum ActionLabel {
  /// "Fold" "Check" "Call 30" "Call all-in 18" "Bet 27 (⅔ pot)" "Raise to 90" "All-in 186".
  public static func long(_ action: Action, context: DecisionContext) -> String {
    let legal = context.legal
    switch action {
    case .fold: return "Fold"
    case .check: return "Check"
    case .call: return legal.callIsAllIn ? "Call all-in \(legal.callAmount)" : "Call \(legal.callAmount)"
    case .bet(let to):
      let name = potFractionName(fraction(to: to, context: context))
      return "Bet \(to) (\(name == "pot" ? "pot" : "\(name) pot"))"
    case .raise(let to): return "Raise to \(to)"
    case .allIn:
      if legal.callIsAllIn && legal.canCall { return "Call all-in \(legal.callAmount)" }
      return "All-in \(legal.allInTo ?? legal.committed + legal.stack)"
    }
  }

  /// "Fold" "Check" "Call" "Bet ⅓" "Bet ½" "Bet ⅔" "Bet pot" "Raise ⅔" "All-in".
  public static func short(_ action: Action, context: DecisionContext) -> String {
    switch action {
    case .fold: return "Fold"
    case .check: return "Check"
    case .call: return "Call"
    case .bet(let to): return "Bet \(potFractionName(fraction(to: to, context: context)))"
    case .raise(let to): return "Raise \(potFractionName(fraction(to: to, context: context)))"
    case .allIn: return context.legal.callIsAllIn && context.legal.canCall ? "Call" : "All-in"
    }
  }

  /// The nearest of "⅓", "½", "⅔", "¾", "pot", "1.5×", "2×".
  public static func potFractionName(_ fraction: Double) -> String {
    let names: [(Double, String)] = [
      (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾"), (1, "pot"), (1.5, "1.5×"), (2, "2×"),
    ]
    var best = names[0]
    for entry in names.dropFirst() where abs(entry.0 - fraction) < abs(best.0 - fraction) { best = entry }
    return best.1
  }

  /// The size as a fraction of the pot after calling (the inverse of `ActionDistribution.potSizedRaises`).
  static func fraction(to: Int, context: DecisionContext) -> Double {
    let legal = context.legal
    let base = Double(context.pot + legal.callAmount)
    guard base > 0 else { return 1 }
    return Double(to - legal.currentBet) / base
  }
}
