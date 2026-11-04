public struct SessionScore: Codable, Sendable, Hashable {
  public var hands = 0
  public var decisions = 0
  public var counts = GradeCounts()
  public var weightedQuality = 0.0
  public var weight = 0.0
  public var netChips = 0
  public var luckChips = 0.0
  public var evLossBB = 0.0

  public init() {}

  /// `100 · Σwq / Σw`; nil without graded decisions.
  public var decisionScore: Double? { weight > 0 ? 100 * weightedQuality / weight : nil }
}

/// Accumulates hand analyses into the session's decision score.
public struct SessionScorer: Sendable {
  public private(set) var score = SessionScore()

  public init() {}

  public mutating func add(_ analysis: HandAnalysis) {
    score.hands += 1
    score.decisions += analysis.decisions.count
    score.counts.good += analysis.counts.good
    score.counts.smallMiss += analysis.counts.smallMiss
    score.counts.leak += analysis.counts.leak
    score.weightedQuality += analysis.weightedQuality
    score.weight += analysis.weight
    score.netChips += analysis.netChips
    score.luckChips += analysis.luck.luckChips
    score.evLossBB += analysis.evLossBB
  }
}
