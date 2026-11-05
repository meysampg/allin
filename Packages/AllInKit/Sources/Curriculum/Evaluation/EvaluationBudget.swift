import Foundation
import PokerAI
import PokerAnalysis

/// How much work an evaluation may do.
public struct EvaluationBudget: Sendable, Hashable {
  public var ev: EVBudget
  public var equitySamples: Int
  public var tracker: RangeTrackerOptions

  public init(ev: EVBudget, equitySamples: Int, tracker: RangeTrackerOptions) {
    self.ev = ev
    self.equitySamples = equitySamples
    self.tracker = tracker
  }

  public static let lesson = EvaluationBudget(
    ev: EVBudget(rolloutsPerCandidate: 240, policyStreets: 2), equitySamples: 4_000, tracker: .standard)
  public static let validation = lesson
  public static let test = EvaluationBudget(ev: .test, equitySamples: 1_000, tracker: .standard)
}
