import Foundation

public enum CoachLevel: String, Codable, Sendable, CaseIterable { case full, questions, hidden }
public enum CoachTier: String, Sendable { case beginner, standard }
public enum CoachQuestionTopic: String, Sendable { case ranges, equity, actionPurpose }

public struct CoachQuestion: Sendable, Hashable {
  public let topic: CoachQuestionTopic
  /// May contain the placeholder {villain}.
  public let text: String

  public init(topic: CoachQuestionTopic, text: String) {
    self.topic = topic
    self.text = text
  }
}

/// Hint fading: the better a skill meter, the less the coach gives away.
public enum CoachEngine {
  /// < 0.40 full; 0.40...0.75 questions; > 0.75 hidden.
  public static func level(meter: Double) -> CoachLevel {
    if meter < 0.40 { return .full }
    if meter <= 0.75 { return .questions }
    return .hidden
  }

  /// Level of the mean meter; empty → full.
  public static func level(meters: [Double]) -> CoachLevel {
    guard !meters.isEmpty else { return .full }
    return level(meter: meters.reduce(0, +) / Double(meters.count))
  }

  public static func showsRangeButton(_ level: CoachLevel) -> Bool { level == .full }

  public static func thinkFirst(tier: CoachTier) -> [CoachQuestion] {
    switch tier {
    case .beginner:
      return [
        CoachQuestion(topic: .ranges, text: "What hands does {villain} play like this?"),
        CoachQuestion(topic: .equity, text: "How does your hand do against those?"),
        CoachQuestion(topic: .actionPurpose, text: "What does each of your moves achieve?"),
      ]
    case .standard:
      return [
        CoachQuestion(topic: .ranges, text: "What is {villain}'s range here?"),
        CoachQuestion(topic: .equity, text: "What is your equity against it?"),
      ]
    }
  }

  /// Venue 0 is the beginner tier.
  public static func tier(forVenueIndex i: Int) -> CoachTier { i <= 0 ? .beginner : .standard }
}
