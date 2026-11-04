import PokerCore
import PokerEquity

/// Postflop decisions of ``BaselineStrategy``: equity against perceived ranges, value bets and balanced bluffs,
/// defence by minimum defence frequency.
enum BaselinePostflop {
  /// Bets and raises that commit this share of the stack or more become all-in.
  private static let allInShare = 0.45
  /// Weak hands need at least this share of the pot odds in equity to defend by frequency alone.
  private static let frequencyDefenceEquity = 0.6
  private static let rangeAdvantageGap = 0.08

  static func distribution(
    for ctx: DecisionContext, spot: SpotFeatures, config: BaselineConfig
  ) -> ActionDistribution {
    var plan = BaselineActionPlan(ctx.legal)
    let opponents = spot.liveOpponents
    guard !opponents.isEmpty, ctx.board.count >= 3 else {
      plan.add(plan.passive, 1)
      return plan.distribution(randomness: 0)
    }
    let hole = ctx.holeCards
    let boardCount = ctx.board.count

    // Perceived ranges, one board strength table per board prefix.
    var tables: [Int: BoardStrengthTable] = [:]
    let villains = opponents.map {
      PerceivedRange.estimate(of: $0, in: ctx, blur: config.rangeBlur, tables: &tables)
    }
    let table: BoardStrengthTable
    if let cached = tables[boardCount] {
      table = cached
    } else {
      table = BoardStrengthTable(board: ctx.board)
      tables[boardCount] = table
    }

    // Villains continue against a bet with the top part of their range.
    let callRanges = villains.map { range -> HandRange in
      let percentiles = table.percentiles(in: range)
      var weights = range.weights
      for i in 0..<1326 where weights[i] > 0 && Double(percentiles[i]) > config.callingRangeTop { weights[i] = 0 }
      return HandRange(weights: weights)
    }
    let seed = StableSeed.of(ctx)
    let eqAll = EquityCalculator.heroEquity(
      hole: hole, vs: villains, board: ctx.board, samples: config.equitySamples, seed: seed)
    let eqCall = EquityCalculator.heroEquity(
      hole: hole, vs: callRanges, board: ctx.board, samples: config.equitySamples, seed: StableSeed.mix(seed, 1))

    // The hero's own perceived range (from the cards it could have), for balance and defence.
    let ownContext = DecisionContext(
      config: ctx.config, seat: ctx.seat, holeCards: [], board: ctx.board, street: ctx.street,
      button: ctx.button, smallBlindSeat: ctx.smallBlindSeat, bigBlindSeat: ctx.bigBlindSeat, seats: ctx.seats,
      pot: ctx.pot, history: ctx.history, legal: ctx.legal)
    let own = PerceivedRange.estimate(of: ctx.seat, in: ownContext, blur: 0, tables: &tables)
    let heroStrength = table.strength(of: Combo(hole[0], hole[1]))
    var ownTotal = 0.0
    var ownBetter = 0.0
    var ownValue = 0.0
    var ownStrengthSum = 0.0
    for i in 0..<1326 {
      let w = Double(own.weights[i])
      if w <= 0 { continue }
      let s = table.strength(of: Combo.all[i])
      ownTotal += w
      ownStrengthSum += w * Double(s)
      if s > heroStrength { ownBetter += w } else if s == heroStrength { ownBetter += 0.5 * w }
      if s >= 0.7 { ownValue += w }
    }
    let ownPercentile = ownTotal > 0 ? ownBetter / ownTotal : 0.5
    let valueShare = ownTotal > 0 ? min(ownValue / ownTotal, 0.95) : 0.2
    var villainStrength = 0.0
    var villainWeight = 0.0
    for range in villains {
      for i in 0..<1326 {
        let w = Double(range.weights[i])
        if w > 0 {
          villainStrength += w * Double(table.strength(of: Combo.all[i]))
          villainWeight += w
        }
      }
    }
    let ownMean = ownTotal > 0 ? ownStrengthSum / ownTotal : 0.5
    let villainMean = villainWeight > 0 ? villainStrength / villainWeight : 0.5
    let rangeAdvantage = ownMean - villainMean > rangeAdvantageGap

    let features = HandFeatures(hole: hole, board: ctx.board)
    let extra = Double(opponents.count - 1)
    let valueThreshold = config.threshold(ctx.street) + 0.04 * extra
    let legal = ctx.legal
    let pot = Double(ctx.pot)

    if legal.toCall == 0 {
      // MARK: Not facing a bet
      let wetness = features.texture.wetness
      let baseSize = wetness < 0.35 ? config.drySize : (wetness < 0.65 ? config.mediumSize : config.wetSize)
      if eqCall >= valueThreshold {
        let size = ctx.street == .river && eqCall >= 0.78 ? config.riverPolarSize : baseSize
        plan.add(betAction(plan, ctx, fraction: size), 0.92)
      } else if rangeAdvantage && ctx.street == .flop && eqCall >= valueThreshold - 0.06 {
        plan.add(betAction(plan, ctx, fraction: config.drySize), 0.6)
      } else if eqAll < 0.35 {
        let size = ctx.street == .river ? config.riverPolarSize : baseSize
        let b = size * pot
        let ratio = ctx.street == .river ? b / (pot + 2 * b) : b / (pot + b) * 0.6
        var p = min(max(ratio * valueShare / (1 - valueShare), 0), 1) * config.bluffRatioScale
        if features.draws.outs >= 8 { p *= 1.5 }
        if features.draws.backdoorFlush || features.draws.backdoorStraight { p *= 1.2 }
        if ctx.street == .river && holdsNutSuitBlocker(hole: hole, board: ctx.board) { p *= 1.3 }
        if opponents.count > 1 { p *= 0.35 }
        if rangeAdvantage { p *= 1.2 }
        plan.add(betAction(plan, ctx, fraction: size), min(p, 1))
      }
    } else {
      // MARK: Facing a bet
      let call = Double(legal.callAmount)
      let potBefore = max(pot - call, 1)
      let mdf = potBefore / (potBefore + call)
      let potOdds = ctx.potOdds
      let defends =
        ownPercentile <= mdf * config.mdfFactor && eqAll >= frequencyDefenceEquity * potOdds || eqAll >= potOdds
      var raiseWeight = 0.0
      if legal.raiseRange != nil || legal.canAllIn {
        if eqCall >= valueThreshold + 0.12 {
          raiseWeight = 0.9
        } else if features.draws.isCombo && ctx.board.count < 5 {
          raiseWeight = 0.3
        }
      }
      if raiseWeight > 0 {
        let target = Double(legal.currentBet) + 0.75 * (pot + call)
        plan.addRaise(to: Int(target.rounded()), allInShare: allInShare, raiseWeight)
      }
      if defends { plan.add(plan.callAction, 1 - raiseWeight) }
    }
    return plan.distribution(randomness: config.randomness)
  }

  /// A bet of `fraction` of the pot (all-in when it commits most of the stack).
  private static func betAction(
    _ plan: BaselineActionPlan, _ ctx: DecisionContext, fraction: Double
  ) -> Action? {
    plan.raiseAction(to: Int((fraction * Double(ctx.pot)).rounded()), allInShare: allInShare)
  }

  /// The hero holds the ace of a suit with three or more board cards, or the king when the ace is on the board.
  private static func holdsNutSuitBlocker(hole: [Card], board: [Card]) -> Bool {
    for suit in Suit.allCases {
      let onBoard = board.filter { $0.suit == suit }
      guard onBoard.count >= 3 else { continue }
      let aceOnBoard = onBoard.contains { $0.rank == .ace }
      for card in hole where card.suit == suit {
        if card.rank == .ace || (aceOnBoard && card.rank == .king) { return true }
      }
    }
    return false
  }
}
