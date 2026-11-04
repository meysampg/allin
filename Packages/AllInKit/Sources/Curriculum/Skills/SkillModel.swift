import Foundation

/// Identifies a spaced-repetition card: a template and the class of its correct answer. Template ids never contain "#".
public struct DecisionTypeKey: Hashable, Codable, Sendable, CustomStringConvertible {
  public let templateID: String
  public let answerClass: String

  public init(templateID: String, answerClass: String) {
    self.templateID = templateID
    self.answerClass = answerClass
  }

  /// Splits at the last "#".
  public init?(rawValue: String) {
    guard let i = rawValue.lastIndex(of: "#") else { return nil }
    self.templateID = String(rawValue[rawValue.startIndex..<i])
    self.answerClass = String(rawValue[rawValue.index(after: i)...])
  }

  public var rawValue: String { "\(templateID)#\(answerClass)" }
  public var description: String { rawValue }
}

public struct SkillRating: Codable, Sendable, Hashable {
  public var theta: Double
  public var evidence: Int
  public var updatedAt: Date?

  public init(theta: Double, evidence: Int, updatedAt: Date?) {
    self.theta = theta
    self.evidence = evidence
    self.updatedAt = updatedAt
  }

  public static let initial = SkillRating(theta: -1.5, evidence: 0, updatedAt: nil)
}

/// Elo-style skill ratings on a logistic scale. Plain inputs only.
public struct SkillModel: Sendable, Hashable {
  public static let masteryMeter = 0.8
  public static let masteryEvidence = 15

  public var ratings: [String: SkillRating]

  public init(ratings: [String: SkillRating] = [:]) {
    self.ratings = ratings
  }

  private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

  /// 4 · (clamp(d, 0, 1) − 0.5)
  public static func difficultyLogit(_ d: Double) -> Double {
    4 * (min(max(d, 0), 1) - 0.5)
  }

  /// 0.1 + 0.3 · exp(−evidence / 8)
  public static func kFactor(evidence: Int) -> Double {
    0.1 + 0.3 * exp(-Double(evidence) / 8)
  }

  public func rating(_ skill: String) -> SkillRating { ratings[skill] ?? .initial }

  public func expected(_ skill: String, difficulty: Double) -> Double {
    Self.sigmoid(rating(skill).theta - Self.difficultyLogit(difficulty))
  }

  @discardableResult
  public mutating func record(skill: String, difficulty: Double, quality: Double, at: Date) -> SkillRating {
    var r = rating(skill)
    let e = Self.sigmoid(r.theta - Self.difficultyLogit(difficulty))
    r.theta += Self.kFactor(evidence: r.evidence) * (min(max(quality, 0), 1) - e)
    r.evidence += 1
    r.updatedAt = at
    ratings[skill] = r
    return r
  }

  public func meter(_ skill: String, baseDifficulty: Double) -> Double {
    let r = rating(skill)
    if r.evidence == 0 { return 0 }
    return Self.sigmoid(r.theta - Self.difficultyLogit(baseDifficulty))
  }

  public func isMastered(_ skill: String, baseDifficulty: Double) -> Bool {
    rating(skill).evidence >= Self.masteryEvidence && meter(skill, baseDifficulty: baseDifficulty) >= Self.masteryMeter
  }

  /// Mean of the skills' meters; a skill with no base difficulty uses 0.5. Empty → 0.
  public func groupMeter(_ skills: [String], baseDifficulty: [String: Double]) -> Double {
    if skills.isEmpty { return 0 }
    let sum = skills.reduce(0.0) { $0 + meter($1, baseDifficulty: baseDifficulty[$1] ?? 0.5) }
    return sum / Double(skills.count)
  }

  /// Per axis: Σ w·meter / Σ w (axes with zero total weight score 0).
  public func axisScores(
    axisWeights: [String: [String: Double]], baseDifficulty: [String: Double]
  ) -> [String: Double] {
    var out: [String: Double] = [:]
    for (axis, weights) in axisWeights {
      var num = 0.0
      var den = 0.0
      for skill in weights.keys.sorted() {
        let w = weights[skill] ?? 0
        num += w * meter(skill, baseDifficulty: baseDifficulty[skill] ?? 0.5)
        den += w
      }
      out[axis] = den > 0 ? num / den : 0
    }
    return out
  }

  /// Inverse of `meter` for evidence > 0, used for demo seeding.
  public static func theta(forMeter m: Double, baseDifficulty: Double) -> Double {
    let c = min(max(m, 1e-6), 1 - 1e-6)
    return log(c / (1 - c)) + difficultyLogit(baseDifficulty)
  }
}
