// Ported from Kata (KataKit/Sources/KataSRS/FSRSScheduler.swift); arithmetic unchanged.
import Foundation

/// FSRS-5 scheduler (default parameters, see docs/ARCHITECTURE.md §4a).
public struct FSRSScheduler: Sendable {
  public let parameters: FSRSParameters
  public let calendar: Calendar

  private static let decay = -0.5
  private static let factor = 19.0 / 81.0

  public init(parameters: FSRSParameters = FSRSParameters(), calendar: Calendar = .current) {
    self.parameters = parameters
    self.calendar = calendar
  }

  // MARK: Public API

  public func retrievability(_ c: FSRSCard, at now: Date) -> Double {
    guard let last = c.lastReview, c.stability > 0 else { return 1 }
    let t = max(0, now.timeIntervalSince(last) / 86400)
    return Self.retrievability(t: t, s: c.stability)
  }

  public func next(_ c: FSRSCard, rating: FSRSRating, now: Date) -> SchedulingResult {
    let (t, plans) = plan(c, now: now)
    return finish(c, rating: rating, now: now, elapsed: t, plans: plans)
  }

  public func preview(_ c: FSRSCard, now: Date) -> [FSRSRating: SchedulingResult] {
    let (t, plans) = plan(c, now: now)
    var out: [FSRSRating: SchedulingResult] = [:]
    for r in FSRSRating.allCases {
      out[r] = finish(c, rating: r, now: now, elapsed: t, plans: plans)
    }
    return out
  }

  // MARK: Formulas

  static func retrievability(t: Double, s: Double) -> Double {
    pow(1 + factor * t / s, decay)
  }

  private var w: [Double] { parameters.w }

  private func clampD(_ x: Double) -> Double { min(max(x, 1), 10) }

  private func d0Raw(_ g: Int) -> Double { w[4] - exp(w[5] * Double(g - 1)) + 1 }

  private func initialDifficulty(_ g: Int) -> Double { clampD(d0Raw(g)) }

  private func nextDifficulty(_ d: Double, _ g: Int) -> Double {
    clampD(w[7] * d0Raw(4) + (1 - w[7]) * (d + (-w[6] * Double(g - 3)) * (10 - d) / 9))
  }

  private func recallStability(d: Double, s: Double, r: Double, rating: FSRSRating) -> Double {
    let hard = rating == .hard ? w[15] : 1
    let easy = rating == .easy ? w[16] : 1
    return s * (exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hard * easy + 1)
  }

  private func forgetStability(d: Double, s: Double, r: Double) -> Double {
    min(
      w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r)),
      s / exp(w[17] * w[18]))
  }

  private func shortTermStability(s: Double, g: Int) -> Double {
    s * exp(w[17] * (Double(g - 3) + w[18]))
  }

  private func interval(forStability s: Double) -> Int {
    let r = parameters.desiredRetention
    let raw = s / Self.factor * (pow(r, 1 / Self.decay) - 1)
    let i = Int(raw.rounded())
    return min(max(i, 1), parameters.maximumInterval)
  }

  private func elapsedDays(_ c: FSRSCard, now: Date) -> Int {
    guard let last = c.lastReview else { return 0 }
    let a = calendar.startOfDay(for: last)
    let b = calendar.startOfDay(for: now)
    let d = calendar.dateComponents([.day], from: a, to: b).day ?? 0
    return max(0, d)
  }

  // MARK: Planning

  private struct Plan {
    var stability: Double
    var difficulty: Double
    var state: FSRSCardState
    var lapsesDelta: Int
    var minuteStep: Bool
    var interval: Int
  }

  private func plan(_ c: FSRSCard, now: Date) -> (Double, [FSRSRating: Plan]) {
    let t = elapsedDays(c, now: now)
    var plans: [FSRSRating: Plan] = [:]
    for rating in FSRSRating.allCases {
      plans[rating] = rawPlan(c, rating: rating, t: t, now: now)
    }
    // Interval ordering for hard / good / easy.
    if var hard = plans[.hard], var good = plans[.good], var easy = plans[.easy] {
      hard.interval = min(hard.interval, good.interval)
      good.interval = max(good.interval, hard.interval + 1)
      easy.interval = max(easy.interval, good.interval + 1)
      let m = parameters.maximumInterval
      hard.interval = min(hard.interval, m)
      good.interval = min(good.interval, m)
      easy.interval = min(easy.interval, m)
      plans[.hard] = hard
      plans[.good] = good
      plans[.easy] = easy
    }
    return (Double(t), plans)
  }

  private func rawPlan(_ c: FSRSCard, rating: FSRSRating, t: Int, now: Date) -> Plan {
    let g = rating.rawValue
    let again = rating == .again
    switch c.state {
    case .new:
      let s = w[g - 1]
      let d = initialDifficulty(g)
      return Plan(
        stability: s, difficulty: d, state: again ? .learning : .review,
        lapsesDelta: 0, minuteStep: again, interval: again ? 0 : interval(forStability: s))
    case .learning, .relearning:
      return shortTermPlan(c, rating: rating)
    case .review:
      if t == 0 { return shortTermPlan(c, rating: rating) }
      let r = Self.retrievability(t: Double(t), s: c.stability)
      if again {
        let s = max(forgetStability(d: c.difficulty, s: c.stability, r: r), 0.01)
        return Plan(
          stability: s, difficulty: nextDifficulty(c.difficulty, 1), state: .relearning,
          lapsesDelta: 1, minuteStep: true, interval: 0)
      }
      let s = recallStability(d: c.difficulty, s: c.stability, r: r, rating: rating)
      return Plan(
        stability: s, difficulty: nextDifficulty(c.difficulty, g), state: .review,
        lapsesDelta: 0, minuteStep: false, interval: interval(forStability: s))
    }
  }

  private func shortTermPlan(_ c: FSRSCard, rating: FSRSRating) -> Plan {
    let g = rating.rawValue
    let s = max(shortTermStability(s: c.stability, g: g), 0.01)
    let d = nextDifficulty(c.difficulty, g)
    if rating == .again {
      return Plan(
        stability: s, difficulty: d, state: c.state == .review ? .relearning : c.state,
        lapsesDelta: 0, minuteStep: true, interval: 0)
    }
    return Plan(
      stability: s, difficulty: d, state: .review, lapsesDelta: 0, minuteStep: false,
      interval: interval(forStability: s))
  }

  private func finish(_ c: FSRSCard, rating: FSRSRating, now: Date, elapsed: Double, plans: [FSRSRating: Plan])
    -> SchedulingResult
  {
    guard let p = plans[rating] else { return SchedulingResult(card: c, elapsedDays: elapsed, scheduledDays: 0) }
    var card = c
    card.stability = p.stability
    card.difficulty = p.difficulty
    card.state = p.state
    card.reps += 1
    card.lapses += p.lapsesDelta
    card.lastReview = now
    if p.minuteStep {
      card.due = now.addingTimeInterval(Double(parameters.againStepMinutes) * 60)
      return SchedulingResult(card: card, elapsedDays: elapsed, scheduledDays: 0)
    }
    card.due =
      calendar.date(byAdding: .day, value: p.interval, to: now) ?? now.addingTimeInterval(Double(p.interval) * 86400)
    return SchedulingResult(card: card, elapsedDays: elapsed, scheduledDays: Double(p.interval))
  }
}
