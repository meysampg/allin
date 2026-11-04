import PokerCore

/// Exact chip formulas used instead of rollouts when the rest of the hand is a showdown.
public enum ClosedFormEV {
  /// Chips: equity · (pot + toCall) − toCall (pot = `DecisionContext.pot`, current bets included).
  public static func call(equity: Double, pot: Int, toCall: Int) -> Double {
    equity * Double(pot + toCall) - Double(toCall)
  }

  /// Chips: fe · pot + (1 − fe) · (eq · (pot + bet + call) − bet), with call = villain's chips to call.
  public static func bet(foldEquity: Double, equityWhenCalled: Double, pot: Int, bet: Int, call: Int) -> Double {
    foldEquity * Double(pot)
      + (1 - foldEquity) * (equityWhenCalled * Double(pot + bet + call) - Double(bet))
  }

  /// True when exactly one opponent is live, `legal.canCall`, and calling ends all betting (river, or the
  /// opponent is all-in). Checked by applying `.call` to the rebuilt state.
  public static func callClosesAction(_ spot: EVSpot) -> Bool {
    let context = spot.context
    guard context.legal.canCall, context.liveSeats.filter({ $0 != spot.hero }).count == 1,
      let plan = try? RolloutPlan(
        spot: spot, ranges: [:], opponents: [:], hero: nil, seed: 0, policyStreets: 1),
      let prepared = try? plan.prepare(index: 0),
      let step = try? HandReducer.apply(.call, to: prepared.state)
    else { return false }
    return step.state.seatToAct == nil || step.state.isComplete
  }
}
