/// Why a distribution could not be built.
public enum DistributionError: Error, Sendable, Equatable {
  case empty
  /// A weight is negative, NaN or infinite.
  case invalidWeight(Action)
  /// Every weight is zero.
  case zeroTotal
  /// The action is not legal for the seat (see ``LegalActions/validate(_:)``).
  case illegal(Action)
}

/// A probability distribution over concrete legal actions. Bet and raise sizes are exact "to" amounts, so a
/// consumer (grader, range tracker, coach) reads the strategy without interpreting buckets.
public struct ActionDistribution: Sendable, Hashable {
  public struct Entry: Sendable, Hashable {
    public let action: Action
    public let probability: Double
  }

  /// Entries with positive probability, summing to 1. Duplicates are merged; order is fold, check, call, bets
  /// and raises ascending, all-in.
  public let entries: [Entry]
  /// The options the distribution was validated against.
  public let legal: LegalActions

  /// Builds a distribution from non-negative weights (they need not sum to 1). Duplicate actions add up, a bet
  /// or raise to the whole stack is stored as `allIn`, zero weights are dropped.
  public init(weights: [(action: Action, weight: Double)], legal: LegalActions) throws {
    guard !weights.isEmpty else { throw DistributionError.empty }
    var merged: [Action: Double] = [:]
    for (action, weight) in weights {
      guard weight.isFinite, weight >= 0 else { throw DistributionError.invalidWeight(action) }
      guard legal.isLegal(action) else { throw DistributionError.illegal(action) }
      merged[Self.canonical(action, legal: legal), default: 0] += weight
    }
    let total = merged.values.reduce(0, +)
    guard total > 0, total.isFinite else { throw DistributionError.zeroTotal }
    self.legal = legal
    entries = merged.filter { $0.value > 0 }
      .map { Entry(action: $0.key, probability: $0.value / total) }
      .sorted { Self.sortKey($0.action) < Self.sortKey($1.action) }
  }

  /// Uniform over `actions` (duplicates count once).
  public init(uniform actions: [Action], legal: LegalActions) throws {
    var seen = Set<Action>()
    let unique = actions.filter { seen.insert($0).inserted }
    try self.init(weights: unique.map { ($0, 1.0) }, legal: legal)
  }

  /// All probability on one action.
  public init(certain action: Action, legal: LegalActions) throws {
    try self.init(weights: [(action, 1)], legal: legal)
  }

  public var actions: [Action] { entries.map(\.action) }

  public func probability(of action: Action) -> Double {
    let key = Self.canonical(action, legal: legal)
    return entries.first { $0.action == key }?.probability ?? 0
  }

  /// Checks normalization and that every action is legal.
  public func validate(against legal: LegalActions) throws {
    guard !entries.isEmpty else { throw DistributionError.empty }
    for e in entries where !legal.isLegal(e.action) { throw DistributionError.illegal(e.action) }
    let total = entries.reduce(0) { $0 + $1.probability }
    guard abs(total - 1) < 1e-9 else { throw DistributionError.zeroTotal }
  }

  /// Draws an action. Consumes exactly one value of `rng`, so a seeded generator replays the same choice.
  public func sample(using rng: inout some RandomNumberGenerator) -> Action {
    let u = Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    var cumulative = 0.0
    for e in entries {
      cumulative += e.probability
      if u < cumulative { return e.action }
    }
    return entries[entries.count - 1].action
  }

  // MARK: Snapping and sizes

  /// Snaps a bet or raise to the nearest legal "to" amount: clamped to the raise range, a multiple of the chip
  /// unit unless it is the all-in total (ties round up). Returns a bet or raise as ``LegalActions/raiseKind``
  /// says, `allIn` when it reaches the whole stack, and nil when no bet or raise is legal.
  public static func snapRaise(to amount: Int, legal: LegalActions) -> Action? {
    guard let range = legal.raiseRange, let kind = legal.raiseKind else { return nil }
    let unit = legal.chipUnit
    var snapped = (amount + unit / 2) / unit * unit
    if amount < 0 { snapped = range.lowerBound }
    snapped = min(max(snapped, range.lowerBound), range.upperBound)
    if snapped != range.upperBound && snapped % unit != 0 {
      let up = (snapped + unit - 1) / unit * unit
      snapped = up <= range.upperBound ? up : range.upperBound
    }
    return canonical(kind == .bet ? .bet(to: snapped) : .raise(to: snapped), legal: legal)
  }

  /// Bet or raise actions at fractions of the pot (raise to = current bet + fraction of the pot after calling),
  /// each snapped to the legal range. Sorted, without duplicates.
  public static func potSizedRaises(
    fractions: [Double], pot: Int, legal: LegalActions
  ) -> [Action] {
    guard legal.raiseRange != nil else { return [] }
    var result: [Action] = []
    for f in fractions {
      let target = Double(legal.currentBet) + f * Double(pot + legal.callAmount)
      if let a = snapRaise(to: Int(target.rounded()), legal: legal), !result.contains(a) {
        result.append(a)
      }
    }
    return result.sorted { sortKey($0) < sortKey($1) }
  }

  /// A raise to the whole stack is `allIn`; everything else is unchanged.
  static func canonical(_ action: Action, legal: LegalActions) -> Action {
    switch action {
    case .bet(let to), .raise(let to):
      if let range = legal.raiseRange, to == range.upperBound, legal.allInTo == to { return .allIn }
      return action
    default:
      return action
    }
  }

  private static func sortKey(_ action: Action) -> Int {
    switch action {
    case .fold: -3
    case .check: -2
    case .call: -1
    case .bet(let to), .raise(let to): to
    case .allIn: Int.max
    }
  }
}
