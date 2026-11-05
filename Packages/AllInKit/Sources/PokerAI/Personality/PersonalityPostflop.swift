import PokerCore
import PokerEquity

extension PersonalityStrategy {
  /// Postflop policy from the equity against the perceived ranges of the live opponents.
  func postflop(_ ctx: DecisionContext, spot: SpotFeatures, acts: SafeActions, policy: inout PolicyWeights) {
    let features = HandFeatures(hole: ctx.holeCards, board: ctx.board)
    var tables: [Int: BoardStrengthTable] = [:]
    let blur = 1 - params.readSkill
    var ranges = spot.liveOpponents.map {
      PerceivedRange.estimate(of: $0, in: ctx, blur: blur, tables: &tables)
    }
    // A big bet narrows the bettor's perceived range to its strongest hands.
    if ctx.legal.toCall > 0, let bettor = Self.currentBettor(ctx),
      let i = spot.liveOpponents.firstIndex(of: bettor)
    {
      let ratio = Double(ctx.legal.toCall) / Double(max(ctx.pot - ctx.legal.toCall, 1))
      let keepTop = min(1, 0.6 / max(ratio, 0.01))
      if keepTop < 1 {
        let percentiles = BoardStrengthTable(board: ctx.board).percentiles(in: ranges[i])
        var weights = ranges[i].weights
        let weak = Float(0.15 / max(1, ratio))
        for k in 0..<weights.count where weights[k] > 0 && Double(percentiles[k]) > keepTop { weights[k] *= weak }
        ranges[i] = HandRange(weights: weights)
      }
    }
    let equity = EquityCalculator.heroEquity(
      hole: ctx.holeCards, vs: ranges, board: ctx.board, samples: 128, seed: StableSeed.of(ctx))
    if ctx.legal.toCall > 0 {
      facingBet(ctx, spot: spot, acts: acts, features: features, equity: equity, policy: &policy)
    } else {
      notFacingBet(ctx, spot: spot, acts: acts, features: features, equity: equity, policy: &policy)
    }
  }

  private func notFacingBet(
    _ ctx: DecisionContext, spot: SpotFeatures, acts: SafeActions, features: HandFeatures, equity: Double,
    policy: inout PolicyWeights
  ) {
    let sizing = params.sizing
    let nutted = features.bucket == .nutted
    let pValue = soft(equity - params.valueThreshold)
    let pBetValue = pValue * (1 - (nutted ? params.slowplay : 0))

    let bluffBase: Double
    if ctx.street == .flop {
      bluffBase = spot.preflopAggressor == ctx.seat ? params.cbet : bluffWithAir(features)
    } else {
      bluffBase = spot.heroBetPreviousStreet ? params.barrel : bluffWithAir(features)
    }
    let pBetBluff = (1 - pValue) * min(max(bluffBase, 0), 1)

    var used = 0.0
    func bet(fraction: Double, mass: Double, shove: Bool) {
      guard mass > 0 else { return }
      used += mass
      if shove, acts.canShove {
        policy.add(.allIn, mass)
        return
      }
      let big = mass * sizing.overbetFrequency
      if big > 0 { policy.add(acts.bet(fraction: 1.5) ?? acts.passive, big) }
      policy.add(acts.bet(fraction: fraction) ?? acts.passive, mass - big)
    }
    bet(fraction: nutted ? sizing.nutted : sizing.value, mass: pBetValue, shove: spot.spr < 1.2)
    bet(fraction: sizing.bluff, mass: pBetBluff, shove: false)
    policy.add(acts.passive, max(0, 1 - used))
  }

  private func bluffWithAir(_ features: HandFeatures) -> Double {
    params.bluffFreq * (features.draws.outs >= 8 ? 1.5 : 1)
  }

  private func facingBet(
    _ ctx: DecisionContext, spot: SpotFeatures, acts: SafeActions, features: HandFeatures, equity: Double,
    policy: inout PolicyWeights
  ) {
    let need = ctx.potOdds * params.continueThreshold
    let outs = features.draws.outs
    let pRaiseValue = soft(equity - (params.valueThreshold + 0.1)) * (1 - params.slowplay)
    let pRaiseBluff = outs >= 8 ? params.bluffFreq * 0.3 : 0
    let pRaise = min(1, pRaiseValue + pRaiseBluff)
    var pCall = min(max(0, soft(equity - need) - pRaiseValue), 1 - pRaise)
    var pFold = 1 - pRaise - pCall
    let made = features.bucket != .air && features.bucket != .draw
    // Stickiness only works at a cheap price: full up to half-pot, gone for shoves.
    let price = min(max((0.45 - ctx.potOdds) / 0.2, 0), 1)
    let moved = pFold * params.stickiness * price * (made || outs >= 4 ? 1 : 0.4)
    pCall += moved
    pFold -= moved

    if pRaise > 0 {
      let target = Double(ctx.legal.currentBet) * 3
      let raise = spot.spr < 2 && acts.canShove ? Action.allIn : acts.raise(to: target)
      policy.add(raise ?? acts.call, pRaise)
    }
    policy.add(acts.call, pCall)
    policy.add(acts.foldOrCheck, pFold)
  }
}

extension PersonalityStrategy {
  /// The seat that has put the most chips in on the current street.
  fileprivate static func currentBettor(_ ctx: DecisionContext) -> Int? {
    var best: (seat: Int, committed: Int)?
    for entry in ctx.history where entry.street == ctx.street {
      if best == nil || entry.committedAfter > best!.committed { best = (entry.seat, entry.committedAfter) }
    }
    return best?.seat
  }
}
