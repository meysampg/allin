import Foundation
import PokerAI
import PokerCore
import PokerEquity

/// Everything the line builder needs to know about the table.
struct LinePlan {
  let template: SpotTemplate
  let heroSeat: Int
  /// Involved opponents in template order (`villain` is the first, `villain2` the second, ...).
  let villainSeats: [Int]
  /// Hero plus the involved opponents; every other seat folds.
  let involved: Set<Int>
  /// Strategy of every seat: the catalog strategy of its character, else `BaselineStrategy()`.
  let strategies: [Int: any StrategyProvider]
  /// Seats whose scripted actions are checked against their strategy.
  let characterSeats: Set<Int>
  let bigBlind: Int
}

struct LineResult {
  let steps: [HandStep]
  let actions: [Action]
  let history: [ActionEntry]
  let state: HandState
}

/// Plays the action prefix of a spot: tokens, the auto rule, consistency, random mode and the stop rule.
enum LineBuilder {
  static let maxSteps = 200
  static let defaultRandomExtra = 20

  /// Returns the line, or the rejection reason (`line`, `consistency`).
  static func build(
    plan: LinePlan, start: HandStep, using rng: inout SeededRNG
  ) -> Result<LineResult, LineReject> {
    let template = plan.template
    let spec = template.line
    let target = template.board.street
    var step = start
    var steps = [start]
    var records = start.records
    var actions: [Action] = []
    var cursor: [Street: Int] = [:]
    var taken = 0
    let randomCount = spec.random.map { Int.random(in: $0.actions.range, using: &rng) }

    while true {
      let state = step.state
      guard let actor = state.seatToAct, !state.isComplete, let legal = state.legalActions else {
        return .failure(LineReject("line"))
      }
      let street = state.street
      if street > target || actions.count > maxSteps { return .failure(LineReject("line")) }
      // Tokens of an earlier street must all have been played.
      for earlier in Street.allCases where earlier < street {
        if (cursor[earlier] ?? 0) < (spec.streets[earlier]?.count ?? 0) { return .failure(LineReject("line")) }
      }
      let tokens = spec.streets[street] ?? []
      let index = cursor[street] ?? 0
      let stopMatches = matches(spec.stopAt, actor: actor, plan: plan)

      var action: Action
      if let randomCount {
        if street == target && taken >= randomCount && stopMatches { break }
        if taken >= randomCount + defaultRandomExtra { return .failure(LineReject("line")) }
        action = randomAction(
          plan: plan, actor: actor, legal: legal, state: state, passive: taken >= randomCount, using: &rng)
      } else {
        if street == target && index >= tokens.count && stopMatches { break }
        if !plan.involved.contains(actor) {
          action = .fold
        } else if index < tokens.count, roleMatches(tokens[index].role, actor: actor, plan: plan) {
          cursor[street] = index + 1
          let token = tokens[index]
          let context = DecisionContext.make(from: state, for: actor, history: ActionEntry.entries(from: records))!
          guard let translated = translate(token.act, context: context, plan: plan, actor: actor, using: &rng)
          else { return .failure(LineReject("line")) }
          action = translated
          if spec.consistent, plan.characterSeats.contains(actor), token.act != .any {
            guard let checked = consistent(translated, token: token.act, context: context, plan: plan, using: &rng)
            else { return .failure(LineReject("consistency")) }
            action = checked
          }
        } else {
          action = legal.canCheck ? .check : .call
        }
      }
      guard legal.isLegal(action), let next = try? HandReducer.apply(action, to: state) else {
        return .failure(LineReject("line"))
      }
      taken += 1
      actions.append(action)
      records += next.records
      steps.append(next)
      step = next
    }
    return .success(
      LineResult(steps: steps, actions: actions, history: ActionEntry.entries(from: records), state: step.state))
  }

  // MARK: Roles and stop

  static func roleMatches(_ role: LineRole?, actor: Int, plan: LinePlan) -> Bool {
    guard let role else { return true }
    switch role {
    case .hero: return actor == plan.heroSeat
    case .villain: return plan.villainSeats.first == actor
    case .villain2: return plan.villainSeats.count > 1 && plan.villainSeats[1] == actor
    case .villain3: return plan.villainSeats.count > 2 && plan.villainSeats[2] == actor
    }
  }

  static func matches(_ stop: LineStop, actor: Int, plan: LinePlan) -> Bool {
    switch stop {
    case .hero: actor == plan.heroSeat
    case .villain: plan.villainSeats.contains(actor)
    case .any: true
    }
  }

  // MARK: Tokens

  /// The action a token asks for, nil when it is not legal here.
  static func translate(
    _ act: LineAct, context: DecisionContext, plan: LinePlan, actor: Int, using rng: inout SeededRNG
  ) -> Action? {
    let legal = context.legal
    switch act {
    case .fold: return .fold
    case .check: return legal.canCheck ? .check : nil
    case .call, .limp: return legal.canCall ? .call : nil
    case .allIn: return legal.canAllIn ? .allIn : nil
    case .any:
      guard let strategy = plan.strategies[actor] else { return nil }
      return strategy.distribution(for: context).sample(using: &rng)
    case .bet(let size):
      let fraction = size.lo == size.hi ? size.lo : Double.random(in: size.lo...size.hi, using: &rng)
      return ActionDistribution.potSizedRaises(fractions: [fraction], pot: context.pot, legal: legal).first
    case .raise(let multiple):
      return ActionDistribution.snapRaise(
        to: Int((multiple * Double(max(legal.currentBet, plan.bigBlind))).rounded()), legal: legal)
    case .open(let blinds):
      return ActionDistribution.snapRaise(to: Int((blinds * Double(plan.bigBlind)).rounded()), legal: legal)
    }
  }

  /// Checks a scripted action against the actor's strategy: accepted with the strategy's probability for it.
  /// A bet or raise snaps to the strategy's nearest comparable size first (a fixed-size script would almost
  /// never hit a size the strategy actually plays). nil rejects.
  static func consistent(
    _ action: Action, token: LineAct, context: DecisionContext, plan: LinePlan, using rng: inout SeededRNG
  ) -> Action? {
    guard let strategy = plan.strategies[context.seat] else { return nil }
    let distribution = strategy.distribution(for: context)
    var chosen = action
    if let desired = raiseTo(action, legal: context.legal) {
      let legal = context.legal
      let unit = Double(legal.chipUnit)
      var best: (action: Action, gap: Int)?
      for entry in distribution.entries {
        guard let to = raiseTo(entry.action, legal: legal) else { continue }
        let fits: Bool
        if case .bet(let size) = token {
          let fraction = Double(to - legal.currentBet) / Double(max(context.pot + legal.callAmount, 1))
          fits = fraction >= size.lo - 0.06 && fraction <= size.hi + 0.06
        } else {
          fits = Double(abs(to - desired)) <= max(0.25 * Double(desired), unit)
        }
        guard fits else { continue }
        let gap = abs(to - desired)
        if best == nil || gap < best!.gap { best = (entry.action, gap) }
      }
      guard let best else {
        _ = Double.random(in: 0..<1, using: &rng)
        return nil
      }
      chosen = best.action
    }
    let draw = Double.random(in: 0..<1, using: &rng)
    return draw < distribution.probability(of: chosen) ? chosen : nil
  }

  /// The "to" amount of a bet, raise or all-in raise.
  static func raiseTo(_ action: Action, legal: LegalActions) -> Int? {
    switch action {
    case .bet(let to), .raise(let to): to
    case .allIn: legal.raiseRange != nil ? legal.allInTo : nil
    default: nil
    }
  }

  // MARK: Random mode

  static func randomAction(
    plan: LinePlan, actor: Int, legal: LegalActions, state: HandState, passive: Bool, using rng: inout SeededRNG
  ) -> Action {
    let passiveAction: Action = legal.canCheck ? .check : .call
    if passive { return passiveAction }
    let draw = Double.random(in: 0..<1, using: &rng)
    if draw < 0.15 {
      // The hero never folds in a random line, so a decision remains for the hero.
      return legal.toCall > 0 && actor != plan.heroSeat ? .fold : passiveAction
    }
    if draw < 0.70 { return passiveAction }
    let sizes = ActionDistribution.potSizedRaises(fractions: [0.33, 0.5, 0.75, 1], pot: state.pot, legal: legal)
    guard !sizes.isEmpty else { return passiveAction }
    return sizes[Int.random(in: 0..<sizes.count, using: &rng)]
  }
}

struct LineReject: Error {
  let reason: String
  init(_ reason: String) { self.reason = reason }
}
