import Foundation
import PokerAI
import PokerAnalysis
import PokerCore
import PokerEquity

/// policyEV: rollouts against the villains' strategies and tracked ranges.
enum PolicyEVMethod {
  struct Plan: Sendable {
    let context: DecisionContext
    let options: [ResolvedOption]
    let ranges: [Int: HandRange]
    /// The standard candidates first, then one request per option the standard set lacks.
    let requests: [EVRequest]
    let extras: [Action]
  }

  static func plan(_ input: EvalInput, ranges: [Int: HandRange]) throws -> Plan {
    let context = try input.heroContext()
    let instance = input.instance
    let options = try EVOptions.resolve(input.template.question.options ?? [], context: context)
    let spot = EVSpot(start: instance.start, priorActions: instance.actions, context: context)
    let strategies = SpotRanges.strategies(instance, characters: input.characters)
    let seed = StableSeed.mix(instance.seed, 0xEF)
    func request(chosen: Action?) -> EVRequest {
      EVRequest(
        spot: spot, opponentRanges: ranges, opponents: strategies, hero: BaselineStrategy(), chosen: chosen,
        budget: input.budget.ev, seed: seed)
    }
    let standard = Set(ActionEVEstimator.candidates(for: context))
    let extras = options.map(\.action).filter { !standard.contains($0) }
    return Plan(
      context: context, options: options, ranges: ranges,
      requests: [request(chosen: nil)] + extras.map { request(chosen: $0) }, extras: extras)
  }

  static func assemble(_ plan: Plan, results: [ActionEVResult]) throws -> Draft {
    var byAction: [Action: CandidateEV] = [:]
    for candidate in results[0].candidates { byAction[candidate.action] = candidate }
    for (index, action) in plan.extras.enumerated() {
      if let candidate = results[index + 1].candidate(for: action) { byAction[action] = candidate }
    }
    var candidates: [CandidateEV] = []
    for option in plan.options {
      guard let candidate = byAction[option.action] else {
        throw SpotEvaluationError.optionUnavailable(option.token)
      }
      candidates.append(candidate)
    }
    var draft = try EVOptions.draft(context: plan.context, options: plan.options, candidates: candidates)
    draft.villainRanges = plan.ranges
    return draft
  }
}
