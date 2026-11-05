import Foundation
import PokerAnalysis

/// The verdict on one response.
public struct SpotGrade: Sendable, Hashable {
  public let grade: Grade
  public let quality: Double
  public let isCorrect: Bool
  public let evLossBB: Double?
  public let graded: GradedDecision?
  /// "✓ Good call" | "≈ Close: bet ½ was a bit better" | "✗ Folding was better" | "✓ Correct" | "✗ Not quite: Bram wins"
  public let verdictTitle: String
  /// "+1.8 big blinds on average" | "−2.3 bb against the best play" | "Two Pair, Kings and Nines beats Pair of Kings"
  public let verdictDetail: String

  public init(
    grade: Grade, quality: Double, isCorrect: Bool, evLossBB: Double? = nil, graded: GradedDecision? = nil,
    verdictTitle: String, verdictDetail: String
  ) {
    self.grade = grade
    self.quality = quality
    self.isCorrect = isCorrect
    self.evLossBB = evLossBB
    self.graded = graded
    self.verdictTitle = verdictTitle
    self.verdictDetail = verdictDetail
  }
}
