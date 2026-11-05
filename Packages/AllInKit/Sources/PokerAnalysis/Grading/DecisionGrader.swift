import Foundation
import PokerCore

public enum Grade: String, Codable, Sendable, CaseIterable { case good, smallMiss, leak }

public struct GradingTolerance: Codable, Sendable, Hashable {
  /// Floor of the "good" band, in big blinds.
  public var minBB = 0.15
  /// The "good" band as a share of the pot before the decision.
  public var potShare = 0.02
  /// Losses up to this share of the pot are a small miss.
  public var smallMissPotShare = 0.10
  /// Floor of the small-miss band, in big blinds.
  public var minSmallMissBB = 0.5
  /// The "good" band is widened to this many standard errors of the difference between best and chosen.
  public var seMultiplier = 2.0
  /// The share of the pot at which `quality` reaches 0.
  public var qualityPotShare = 0.25

  public init() {}

  public static let standard = GradingTolerance()
}

public struct GradedDecision: Codable, Sendable, Hashable {
  public let chosen: CandidateEV
  public let best: CandidateEV
  public let second: CandidateEV?
  public let candidates: [CandidateEV]
  /// `max(0, best - chosen)` in big blinds.
  public let evLossBB: Double
  /// `max(minBB, potShare * potBefore / BB)`, widened by the sampling error of the best and chosen EVs.
  public let toleranceBB: Double
  /// `second != nil && best - second < toleranceBB`.
  public let isClose: Bool
  public let grade: Grade
  /// `clamp(1 - evLoss / (qualityPotShare * potBefore / BB), 0, 1)`.
  public let quality: Double
  /// `log2(1 + potBefore / BB)`.
  public let weight: Double
  public let potBefore: Int
  public let bigBlind: Int

  public init(
    chosen: CandidateEV, best: CandidateEV, second: CandidateEV?, candidates: [CandidateEV], evLossBB: Double,
    toleranceBB: Double, isClose: Bool, grade: Grade, quality: Double, weight: Double, potBefore: Int,
    bigBlind: Int
  ) {
    self.chosen = chosen
    self.best = best
    self.second = second
    self.candidates = candidates
    self.evLossBB = evLossBB
    self.toleranceBB = toleranceBB
    self.isClose = isClose
    self.grade = grade
    self.quality = quality
    self.weight = weight
    self.potBefore = potBefore
    self.bigBlind = bigBlind
  }
}

public enum DecisionGrader {
  /// Grades `chosen` from the EVs only (never from the hand's result). `chosen` must be one of the candidates
  /// (canonicalized as by `ActionDistribution`); precondition otherwise.
  public static func grade(
    _ evs: ActionEVResult, chosen: Action, potBefore: Int, bigBlind: Int,
    tolerance: GradingTolerance = .standard
  ) -> GradedDecision {
    guard let chosenEV = evs.candidate(for: chosen) else {
      preconditionFailure("The chosen action \(chosen) is not among the candidates")
    }
    let ranked = evs.ranked
    let best = evs.best
    let second = ranked.count > 1 ? ranked[1] : nil
    let potBB = Double(potBefore) / Double(max(bigBlind, 1))
    let baseTol = max(tolerance.minBB, tolerance.potShare * potBB)
    let noise =
      tolerance.seMultiplier
      * (chosenEV.standardError * chosenEV.standardError + best.standardError * best.standardError).squareRoot()
    let tol = max(baseTol, noise)
    let loss = max(0, best.evBB - chosenEV.evBB)
    let isClose = second.map { best.evBB - $0.evBB < tol } ?? false
    let inTopTwo = ranked.prefix(2).contains { $0.action == chosenEV.action }
    let grade: Grade
    if loss <= tol || (isClose && inTopTwo) {
      grade = .good
    } else if loss <= max(tolerance.smallMissPotShare * potBB, tolerance.minSmallMissBB) {
      grade = .smallMiss
    } else {
      grade = .leak
    }
    let scale = tolerance.qualityPotShare * potBB
    let quality = scale > 0 ? min(max(1 - loss / scale, 0), 1) : (loss <= tol ? 1 : 0)
    return GradedDecision(
      chosen: chosenEV, best: best, second: second, candidates: evs.candidates, evLossBB: loss,
      toleranceBB: tol, isClose: isClose, grade: grade, quality: quality,
      weight: log2(1 + potBB), potBefore: potBefore, bigBlind: bigBlind)
  }

  /// The form of `action` used in `ActionEVResult.candidates` (a raise to the whole stack, or a call that puts
  /// the seat all-in, is `.allIn`).
  public static func canonical(_ action: Action, legal: LegalActions) -> Action {
    if action == .call && legal.callIsAllIn && legal.canAllIn { return .allIn }
    guard let distribution = try? ActionDistribution(certain: action, legal: legal),
      let entry = distribution.entries.first
    else { return action }
    return entry.action
  }
}

public struct GradeCounts: Codable, Sendable, Hashable {
  public var good = 0
  public var smallMiss = 0
  public var leak = 0

  public init() {}

  public var total: Int { good + smallMiss + leak }

  public mutating func add(_ grade: Grade) {
    switch grade {
    case .good: good += 1
    case .smallMiss: smallMiss += 1
    case .leak: leak += 1
    }
  }
}
