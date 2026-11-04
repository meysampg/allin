// Ported from Kata (KataKit/Sources/KataSRS/FSRSTypes.swift); arithmetic unchanged.
import Foundation

public enum FSRSRating: Int, Codable, Sendable, CaseIterable {
  case again = 1, hard, good, easy
}

public enum FSRSCardState: Int, Codable, Sendable {
  case new = 0, learning, review, relearning
}

public struct FSRSCard: Codable, Sendable, Hashable {
  public var stability: Double
  public var difficulty: Double
  public var due: Date
  public var lastReview: Date?
  public var reps: Int
  public var lapses: Int
  public var state: FSRSCardState

  public init(
    stability: Double, difficulty: Double, due: Date, lastReview: Date? = nil,
    reps: Int = 0, lapses: Int = 0, state: FSRSCardState = .new
  ) {
    self.stability = stability
    self.difficulty = difficulty
    self.due = due
    self.lastReview = lastReview
    self.reps = reps
    self.lapses = lapses
    self.state = state
  }

  public static func new(now: Date) -> FSRSCard {
    FSRSCard(stability: 0, difficulty: 0, due: now, lastReview: nil, reps: 0, lapses: 0, state: .new)
  }
}

public struct FSRSParameters: Sendable, Hashable {
  public var w: [Double]
  public var desiredRetention: Double
  public var maximumInterval: Int
  public var againStepMinutes: Int

  public static let defaultW: [Double] = [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605,
    2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
  ]

  public init(
    w: [Double] = FSRSParameters.defaultW, desiredRetention: Double = 0.9,
    maximumInterval: Int = 36500, againStepMinutes: Int = 10
  ) {
    self.w = w
    self.desiredRetention = desiredRetention
    self.maximumInterval = maximumInterval
    self.againStepMinutes = againStepMinutes
  }
}

public struct SchedulingResult: Sendable, Hashable {
  public var card: FSRSCard
  public var elapsedDays: Double
  /// 0 for minute-based steps.
  public var scheduledDays: Double

  public init(card: FSRSCard, elapsedDays: Double, scheduledDays: Double) {
    self.card = card
    self.elapsedDays = elapsedDays
    self.scheduledDays = scheduledDays
  }
}
