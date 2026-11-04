import PokerCore
import PokerEquity

extension PersonalityStrategy {
  /// Preflop policy from the hand's percentile in the character's ordering (0 = best).
  func preflop(_ ctx: DecisionContext, spot: SpotFeatures, acts: SafeActions, policy: inout PolicyWeights) {
    let hand = Combo(ctx.holeCards[0], ctx.holeCards[1]).handClass
    let p = ordering.percentile(of: hand)
    let play = playFraction(spot)
    let raiseTop = play * params.pfrRatio
    let line = spot.preflop
    let bb = Double(ctx.config.bigBlind)
    let sizing = params.sizing

    var pFold = 1.0
    func put(_ action: Action, _ weight: Double) {
      guard weight > 0 else { return }
      policy.add(action, weight)
      pFold -= weight
    }
    func putAggressive(_ action: Action?, _ weight: Double) { put(action ?? acts.call, weight) }

    switch line.situation {
    case .unopened, .limped:
      let pr = soft(raiseTop - p)
      let pc = max(0, soft(play - p) - pr)
      let size = (sizing.openRaiseBB + Double(line.limpers)) * bb
      putAggressive(acts.raise(to: size), pr)
      put(acts.passive, pc)

    case .facingOpen:
      let bluff3 = p > play && p < play + 0.1 ? params.bluffFreq * 0.3 : 0
      let p3 = min(1, soft(params.threeBet - p) + bluff3)
      let continueTop = play * (0.55 + 0.45 * params.stickiness)
      let pc = max(0, min(soft(continueTop - p), 1) - p3)
      let oop = spot.isInPosition ? 0.0 : 0.5
      let faced = Double(line.lastRaiseTo)
      let size = faced * (sizing.threeBetMultiplier + oop + Double(line.callersOfLastRaise))
      putAggressive(acts.raise(to: size), p3)
      put(acts.call, pc)

    case .facingThreeBet:
      let keep: Double
      if line.heroRaises > 0 {
        let folded = raiseTop * params.foldTo3Bet
        keep = raiseTop - folded + params.stickiness * 0.3 * folded
      } else {
        keep = play * (0.55 + 0.45 * params.stickiness) * 0.5
      }
      let p4 = soft(0.3 * keep - p)
      let pc = max(0, soft(keep - p) - p4)
      let shove = spot.spr < 3 && acts.canShove
      putAggressive(shove ? .allIn : acts.raise(to: Double(line.lastRaiseTo) * 2.3), p4)
      put(acts.call, pc)

    case .facingFourBetPlus:
      let continueTop = 0.025 + 0.03 * params.stickiness
      let pa = soft(0.015 - p)
      let pc = max(0, soft(continueTop - p) - pa)
      putAggressive(acts.canShove ? .allIn : nil, pa)
      put(acts.call, pc)
    }

    if pFold > 0 {
      if ctx.legal.toCall > 0, sanityFloorPasses(ctx, line: line) {
        policy.add(acts.call, pFold)
      } else {
        policy.add(acts.foldOrCheck, pFold)
      }
    }
  }

  /// Facing a big bet, a hand with enough equity against the (blurred) line range never folds, so the bot
  /// cannot be exploited by wide, aggressive opponents it would otherwise respect too much.
  private func sanityFloorPasses(_ ctx: DecisionContext, line: PreflopLine) -> Bool {
    let odds = ctx.potOdds
    guard odds >= 0.33, let raiser = line.lastRaiser, raiser != ctx.seat else { return false }
    let range = PreflopLineRanges.range(of: raiser, in: ctx).blended(with: .full, t: 1 - params.readSkill)
    let equity = EquityCalculator.heroEquity(
      hole: ctx.holeCards, vs: [range], board: [], samples: 64, seed: StableSeed.of(ctx))
    return equity >= odds * params.continueThreshold
  }
}
