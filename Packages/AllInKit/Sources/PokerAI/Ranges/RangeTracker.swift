import PokerCore
import PokerEquity

/// Exact Bayesian range inference through white-box strategies. Value type; deterministic.
public struct RangeTracker: Sendable {
  /// Posterior per tracked seat, normalized so the largest weight is 1; observer cards and the board removed.
  public private(set) var ranges: [Int: HandRange]
  /// Seats where an update would have zeroed the range; the previous range was kept.
  public private(set) var inconsistentSeats: Set<Int>
  /// Number of actions applied per seat.
  public private(set) var actionsObserved: [Int: Int]
  public let observer: Int?

  private let observerMask: CardSet
  private let strategies: [Int: any StrategyProvider]
  private let options: RangeTrackerOptions

  /// - seats: the seats to track (usually every seat but the observer).
  /// - observer, observerCards: whose cards are dead (the hero); nil/[] for a spectator.
  /// - strategies: white-box policy of each tracked seat. A seat without a strategy keeps its prior.
  /// - priors: default `HandRange.full` for every seat.
  public init(
    seats: [Int], observer: Int?, observerCards: [Card], strategies: [Int: any StrategyProvider],
    priors: [Int: HandRange] = [:], options: RangeTrackerOptions = .standard
  ) {
    self.observer = observer
    self.observerMask = CardSet(observerCards)
    self.strategies = strategies
    self.options = options
    var ranges: [Int: HandRange] = [:]
    for seat in seats {
      ranges[seat] = (priors[seat] ?? .full).removing(CardSet(observerCards))
    }
    self.ranges = ranges
    inconsistentSeats = []
    actionsObserved = [:]
  }

  public func range(of seat: Int) -> HandRange? { ranges[seat] }

  /// P(action | combo) with `context.holeCards` replaced by `combo.cards` (`probability(of:)` canonicalization).
  public static func likelihood(
    of action: Action, combo: Combo, context: DecisionContext, strategy: any StrategyProvider
  ) -> Double {
    Likelihood.probability(of: action, byClass: false, combo: combo, context: context, strategy: strategy)
  }

  // MARK: Updates

  /// Bayes update of `context.seat` for `action`. Ignores seats that are not tracked.
  public mutating func observe(_ context: DecisionContext, action: Action) {
    guard let plan = makePlan(context, action) else { return }
    let exact = plan.items.map { Self.evaluate($0, plan: plan, byClass: false) }
    let fallback: () -> [Double] = { plan.items.map { Self.evaluate($0, plan: plan, byClass: true) } }
    finish(plan, exact: exact, fallback: fallback)
  }

  /// Same result bit for bit, work split into `options.chunks` TaskGroup chunks.
  public mutating func observe(_ context: DecisionContext, action: Action) async {
    guard let plan = makePlan(context, action) else { return }
    let exact = await Self.parallelEvaluate(plan, byClass: false)
    guard Self.maxWeight(plan: plan, likelihoods: exact) <= 0, plan.strategy != nil else {
      finish(plan, exact: exact, fallback: { [] })
      return
    }
    let fallback = await Self.parallelEvaluate(plan, byClass: true)
    finish(plan, exact: exact, fallback: { fallback })
  }

  /// Applies every point whose actor is tracked (the observer's own points are skipped).
  public mutating func observe(_ points: [DecisionPoint]) async {
    for point in points where point.context.seat != observer && ranges[point.context.seat] != nil {
      await observe(point.context, action: point.action)
    }
  }

  // MARK: Internals

  private struct Plan: Sendable {
    let seat: Int
    let context: DecisionContext
    let action: Action
    let strategy: (any StrategyProvider)?
    let prior: HandRange
    let dead: CardSet
    /// One representative or live combo per item.
    let items: [Combo]
    /// For class mode, the live combos each item stands for; otherwise empty (item = itself).
    let groups: [[Combo]]
    let chunks: Int
    let pruneBelow: Float
  }

  private func makePlan(_ context: DecisionContext, _ action: Action) -> Plan? {
    let seat = context.seat
    guard let prior = ranges[seat] else { return nil }
    let dead = observerMask.union(CardSet(context.board))
    let weights = prior.weights
    var items: [Combo] = []
    var groups: [[Combo]] = []
    if context.street == .preflop && options.preflopByClass {
      for handClass in HandClass.all {
        let live = handClass.combos.filter { weights[$0.index] > 0 && $0.mask.isDisjoint(with: dead) }
        if let first = live.first {
          items.append(first)
          groups.append(live)
        }
      }
    } else {
      for combo in Combo.all where weights[combo.index] > 0 && combo.mask.isDisjoint(with: dead) {
        items.append(combo)
        groups.append([combo])
      }
    }
    return Plan(
      seat: seat, context: context, action: action, strategy: strategies[seat], prior: prior, dead: dead,
      items: items, groups: groups, chunks: max(1, options.chunks), pruneBelow: options.pruneBelow)
  }

  private static func evaluate(_ combo: Combo, plan: Plan, byClass: Bool) -> Double {
    guard let strategy = plan.strategy else { return 1 }
    return Likelihood.probability(
      of: plan.action, byClass: byClass, combo: combo, context: plan.context, strategy: strategy)
  }

  private static func parallelEvaluate(_ plan: Plan, byClass: Bool) async -> [Double] {
    let count = plan.items.count
    guard count > 0 else { return [] }
    let chunkCount = min(plan.chunks, count)
    let size = (count + chunkCount - 1) / chunkCount
    return await withTaskGroup(of: (Int, [Double]).self) { group in
      for chunk in 0..<chunkCount {
        let lower = chunk * size
        let upper = min(count, lower + size)
        guard lower < upper else { continue }
        group.addTask {
          (chunk, (lower..<upper).map { evaluate(plan.items[$0], plan: plan, byClass: byClass) })
        }
      }
      var parts = [[Double]](repeating: [], count: chunkCount)
      for await (index, values) in group { parts[index] = values }
      return parts.flatMap { $0 }
    }
  }

  private static func newWeights(plan: Plan, likelihoods: [Double]) -> [Float] {
    var weights = plan.prior.weights
    for combo in Combo.all where !combo.mask.isDisjoint(with: plan.dead) { weights[combo.index] = 0 }
    for (item, group) in plan.groups.enumerated() {
      let factor = likelihoods[item]
      for combo in group { weights[combo.index] = Float(Double(weights[combo.index]) * factor) }
    }
    // Live combos with positive prior weight are exactly the grouped ones; everything else is already 0.
    var live = Set<Int>()
    for group in plan.groups { for combo in group { live.insert(combo.index) } }
    for index in weights.indices where !live.contains(index) { weights[index] = 0 }
    return weights
  }

  private static func maxWeight(plan: Plan, likelihoods: [Double]) -> Float {
    newWeights(plan: plan, likelihoods: likelihoods).max() ?? 0
  }

  private mutating func finish(_ plan: Plan, exact: [Double], fallback: () -> [Double]) {
    actionsObserved[plan.seat, default: 0] += 1
    guard plan.strategy != nil else {
      ranges[plan.seat] = plan.prior.removing(plan.dead)
      return
    }
    var weights = Self.newWeights(plan: plan, likelihoods: exact)
    var peak = weights.max() ?? 0
    if peak <= 0 {
      let byClass = fallback()
      if byClass.count == plan.items.count {
        weights = Self.newWeights(plan: plan, likelihoods: byClass)
        peak = weights.max() ?? 0
      }
    }
    guard peak > 0 else {
      inconsistentSeats.insert(plan.seat)
      ranges[plan.seat] = plan.prior.removing(plan.dead)
      return
    }
    for index in weights.indices {
      let normalized = weights[index] / peak
      weights[index] = normalized < plan.pruneBelow ? 0 : normalized
    }
    ranges[plan.seat] = HandRange(weights: weights)
  }
}
