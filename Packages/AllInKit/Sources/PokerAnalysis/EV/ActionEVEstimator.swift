import PokerCore
import PokerEquity

public enum EVError: Error, Sendable, Equatable {
  case replayMismatch
  case missingStrategy(seat: Int)
  case invalidSpot(String)
}

public struct EVRequest: Sendable {
  public var spot: EVSpot
  /// Live opponents; a missing or empty range means `HandRange.full`.
  public var opponentRanges: [Int: HandRange]
  /// Every live opponent.
  public var opponents: [Int: any StrategyProvider]
  /// Continuation policy (`BaselineStrategy()`).
  public var hero: any StrategyProvider
  /// Always evaluated, even if not a standard candidate.
  public var chosen: Action?
  public var budget: EVBudget
  public var seed: UInt64

  public init(
    spot: EVSpot, opponentRanges: [Int: HandRange], opponents: [Int: any StrategyProvider],
    hero: any StrategyProvider, chosen: Action?, budget: EVBudget, seed: UInt64
  ) {
    self.spot = spot
    self.opponentRanges = opponentRanges
    self.opponents = opponents
    self.hero = hero
    self.chosen = chosen
    self.budget = budget
    self.seed = seed
  }
}

/// Estimates the EV of each candidate action by common-random-number rollouts (or closed forms).
public enum ActionEVEstimator {
  static let betFractions: [Double] = [1.0 / 3, 1.0 / 2, 2.0 / 3, 1]

  /// Fold (only if toCall > 0); check or call (`.allIn` when the call is all-in); pot-sized raises
  /// [1/3, 1/2, 2/3, 1]; `.allIn` if available; plus `chosen`. Deduplicated, canonical order.
  public static func candidates(for context: DecisionContext, including chosen: Action? = nil) -> [Action] {
    let legal = context.legal
    var result: [Action] = []
    if legal.toCall > 0 { result.append(.fold) }
    if legal.canCheck { result.append(.check) }
    if legal.canCall { result.append(legal.callIsAllIn ? .allIn : .call) }
    result += ActionDistribution.potSizedRaises(fractions: betFractions, pot: context.pot, legal: legal)
    if legal.canAllIn { result.append(.allIn) }
    if let chosen, let canonical = canonical(chosen, legal: legal) { result.append(canonical) }
    var seen = Set<Action>()
    return result.filter { seen.insert($0).inserted }.sorted { sortKey($0) < sortKey($1) }
  }

  public static func estimate(_ request: EVRequest) async throws -> ActionEVResult {
    let work = try prepare(request)
    var chunkResults: [[[Double]]] = Array(repeating: [], count: work.ranges.count)
    if !work.rolloutActions.isEmpty {
      try await withThrowingTaskGroup(of: (Int, [[Double]]).self) { group in
        for (c, range) in work.ranges.enumerated() {
          let plan = work.plan
          let actions = work.rolloutActions
          group.addTask { (c, try runChunk(plan, actions: actions, indices: range)) }
        }
        for try await (c, values) in group { chunkResults[c] = values }
      }
    }
    return assemble(work, chunkResults: chunkResults)
  }

  public static func estimateSerial(_ request: EVRequest) throws -> ActionEVResult {
    let work = try prepare(request)
    var chunkResults: [[[Double]]] = []
    for range in work.ranges {
      chunkResults.append(
        work.rolloutActions.isEmpty ? [] : try runChunk(work.plan, actions: work.rolloutActions, indices: range))
    }
    return assemble(work, chunkResults: chunkResults)
  }

  // MARK: Work

  private struct Work {
    let request: EVRequest
    let plan: RolloutPlan
    let candidates: [Action]
    let rolloutActions: [Action]
    let closedForm: [Action: CandidateEV]
    let ranges: [Range<Int>]
  }

  private static func prepare(_ request: EVRequest) throws -> Work {
    let spot = request.spot
    let context = spot.context
    if let chosen = request.chosen, canonical(chosen, legal: context.legal) == nil {
      throw EVError.invalidSpot("The chosen action is not legal")
    }
    let plan = try RolloutPlan(
      spot: spot, ranges: request.opponentRanges, opponents: request.opponents, hero: request.hero,
      seed: request.seed, policyStreets: request.budget.policyStreets)
    // Replay once up front so a corrupted log fails even when every candidate is exact.
    _ = try plan.prepare(index: 0)
    let candidates = candidates(for: context, including: request.chosen)
    var closed: [Action: CandidateEV] = [:]
    if ClosedFormEV.callClosesAction(spot), let callLike = callLikeAction(context.legal),
      candidates.contains(callLike), let ev = closedFormCall(request, plan: plan, action: callLike)
    {
      closed[callLike] = ev
    }
    let rolloutActions = candidates.filter { $0 != .fold && closed[$0] == nil }
    let n = max(request.budget.rolloutsPerCandidate, 1)
    let chunkCount = max(1, min(request.budget.chunks, n))
    let size = (n + chunkCount - 1) / chunkCount
    let ranges = stride(from: 0, to: n, by: size).map { $0..<min($0 + size, n) }
    return Work(
      request: request, plan: plan, candidates: candidates, rolloutActions: rolloutActions, closedForm: closed,
      ranges: ranges)
  }

  /// Values of every action for rollouts `indices`, shaped [action][index - lowerBound].
  private static func runChunk(_ plan: RolloutPlan, actions: [Action], indices: Range<Int>) throws -> [[Double]] {
    var values = [[Double]](repeating: [], count: actions.count)
    for i in indices {
      let prepared = try plan.prepare(index: i)
      for (a, action) in actions.enumerated() {
        values[a].append(try plan.play(action, from: prepared))
      }
    }
    return values
  }

  private static func assemble(_ work: Work, chunkResults: [[[Double]]]) -> ActionEVResult {
    let context = work.request.spot.context
    var out: [CandidateEV] = []
    for action in work.candidates {
      let label = ActionLabel.long(action, context: context)
      let short = ActionLabel.short(action, context: context)
      if action == .fold {
        out.append(
          CandidateEV(
            action: action, label: label, shortLabel: short, evBB: 0, standardError: 0, samples: 0,
            method: .exactFold))
      } else if let closed = work.closedForm[action] {
        out.append(closed)
      } else {
        let a = work.rolloutActions.firstIndex(of: action)!
        var values: [Double] = []
        for chunk in chunkResults { values += chunk[a] }
        let (mean, se) = meanAndError(values)
        out.append(
          CandidateEV(
            action: action, label: label, shortLabel: short, evBB: mean, standardError: se,
            samples: values.count, method: .rollout))
      }
    }
    return ActionEVResult(candidates: out)
  }

  private static func meanAndError(_ values: [Double]) -> (Double, Double) {
    guard !values.isEmpty else { return (0, 0) }
    var sum = 0.0
    for v in values { sum += v }
    let mean = sum / Double(values.count)
    guard values.count > 1 else { return (mean, 0) }
    var squares = 0.0
    for v in values { squares += (v - mean) * (v - mean) }
    let sd = (squares / Double(values.count - 1)).squareRoot()
    return (mean, sd / Double(values.count).squareRoot())
  }

  // MARK: Closed form

  private static func callLikeAction(_ legal: LegalActions) -> Action? {
    guard legal.canCall else { return nil }
    return legal.callIsAllIn ? .allIn : .call
  }

  private static func closedFormCall(_ request: EVRequest, plan: RolloutPlan, action: Action) -> CandidateEV? {
    let context = request.spot.context
    guard let villain = plan.activeOpponents.first, let range = plan.ranges[villain] else { return nil }
    let equity: EquityResult
    if context.board.count == 5 {
      equity = EquityCalculator.exact(hero: context.holeCards, vs: range, board: context.board)
    } else {
      var rng = SeededRNG(seed: StableSeed.mix(request.seed, 0xC10))
      equity = EquityCalculator.monteCarlo(
        hero: context.holeCards, vs: [range], board: context.board,
        samples: max(request.budget.rolloutsPerCandidate, 1) * 8, using: &rng)
      if equity.samples == 0 { return nil }
    }
    let toCall = context.legal.callAmount
    let bb = Double(context.config.bigBlind)
    let chips = ClosedFormEV.call(equity: equity.equity, pot: context.pot, toCall: toCall)
    let scale = Double(context.pot + toCall) / bb
    return CandidateEV(
      action: action, label: ActionLabel.long(action, context: context),
      shortLabel: ActionLabel.short(action, context: context), evBB: chips / bb,
      standardError: equity.standardError * scale, samples: equity.samples, method: .closedForm)
  }

  // MARK: Canonical form

  private static func canonical(_ action: Action, legal: LegalActions) -> Action? {
    if action == .call && legal.callIsAllIn { return legal.canAllIn ? .allIn : nil }
    guard let distribution = try? ActionDistribution(certain: action, legal: legal) else { return nil }
    return distribution.entries.first?.action
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
