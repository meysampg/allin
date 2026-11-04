import PokerCore
import PokerEquity

/// Oryn: a robust heuristic reference player. Preflop it follows generated equity-realisation ranges; postflop it
/// compares its equity against perceived ranges, defends against bets by minimum defence frequency and balances
/// its bluffs against its value bets. Pure: the distribution is a function of the context alone (the Monte Carlo
/// seeds come from the context).
public struct BaselineStrategy: StrategyProvider {
  public let config: BaselineConfig
  private let ranges: BaselinePreflopRanges

  public init(config: BaselineConfig = .default) {
    self.config = config
    self.ranges = .generated
  }

  /// Uses a custom preflop range set (tests, experiments).
  public init(config: BaselineConfig, ranges: BaselinePreflopRanges) {
    self.config = config
    self.ranges = ranges
  }

  public func distribution(for context: DecisionContext) -> ActionDistribution {
    let spot = SpotFeatures(context)
    guard context.holeCards.count == 2 else {
      return BaselineActionPlan(context.legal).distribution(randomness: 0)
    }
    if context.street == .preflop || context.board.count < 3 {
      return BaselinePreflop.distribution(for: context, spot: spot, config: config, ranges: ranges)
    }
    return BaselinePostflop.distribution(for: context, spot: spot, config: config)
  }
}

/// Collects the intended actions with probabilities, keeps only legal ones, sends the leftover probability to the
/// passive action (check, else fold) and spreads `randomness` over the actions already used.
struct BaselineActionPlan {
  let legal: LegalActions
  private var entries: [(action: Action, weight: Double)] = []

  init(_ legal: LegalActions) { self.legal = legal }

  /// Check when free, otherwise fold.
  var passive: Action { legal.canCheck ? .check : .fold }

  /// A call, or the all-in that calls for less.
  var callAction: Action? {
    if legal.canCall { return .call }
    return legal.callIsAllIn ? .allIn : nil
  }

  /// A bet or raise to about `amount`, or the all-in when `amount` reaches `allInShare` of the seat's chips.
  func raiseAction(to amount: Int, allInShare: Double) -> Action? {
    let total = legal.committed + legal.stack
    if legal.canAllIn && !legal.callIsAllIn && Double(amount) >= allInShare * Double(total) { return .allIn }
    if let snapped = ActionDistribution.snapRaise(to: amount, legal: legal) { return snapped }
    return legal.canAllIn && !legal.callIsAllIn ? .allIn : nil
  }

  /// A bet or raise to about `amount`; where no raise is possible (an all-in to call, a closed round) the weight
  /// goes to the call instead, or to nothing when nothing is owed.
  mutating func addRaise(to amount: Int, allInShare: Double, _ weight: Double) {
    if let raise = raiseAction(to: amount, allInShare: allInShare) {
      add(raise, weight)
    } else if legal.toCall > 0 {
      add(callAction, weight)
    }
  }

  mutating func add(_ action: Action?, _ weight: Double) {
    guard let action, weight > 0, weight.isFinite, legal.isLegal(action) else { return }
    entries.append((action, weight))
  }

  func distribution(randomness: Double) -> ActionDistribution {
    var merged: [(action: Action, weight: Double)] = []
    var used = 0.0
    for entry in entries {
      used += entry.weight
      if let i = merged.firstIndex(where: { $0.action == entry.action }) {
        merged[i].weight += entry.weight
      } else {
        merged.append(entry)
      }
    }
    if used > 1 {
      for i in merged.indices { merged[i].weight /= used }
    } else if used < 1 {
      let rest = 1 - used
      if let i = merged.firstIndex(where: { $0.action == passive }) {
        merged[i].weight += rest
      } else {
        merged.append((passive, rest))
      }
    }
    let r = min(max(randomness, 0), 1)
    if r > 0 && merged.count > 1 {
      let share = r / Double(merged.count)
      for i in merged.indices { merged[i].weight = (1 - r) * merged[i].weight + share }
    }
    if let result = try? ActionDistribution(weights: merged.map { ($0.action, $0.weight) }, legal: legal) {
      return result
    }
    // Check and fold are always legal for the seat to act, so this cannot throw.
    return try! ActionDistribution(certain: passive, legal: legal)
  }
}
