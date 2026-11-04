// Ported from Kata (KataKit/Sources/KataSRS/StreakCalculator.swift); arithmetic unchanged.
import Foundation

/// Streak maths over sets of active and frozen days. A frozen day bridges a gap without counting.
public enum StreakCalculator {
  /// Counts back from `today` if it is active, otherwise from yesterday.
  public static func current(active: Set<DayKey>, frozen: Set<DayKey>, today: DayKey, calendar: Calendar) -> Int {
    var day = active.contains(today) ? today : today.adding(days: -1, calendar: calendar)
    var streak = 0
    while true {
      if active.contains(day) {
        streak += 1
      } else if !frozen.contains(day) {
        break
      }
      day = day.adding(days: -1, calendar: calendar)
    }
    return streak
  }

  /// Longest run of consecutive covered days, counting only active days.
  public static func longest(active: Set<DayKey>, frozen: Set<DayKey>, calendar: Calendar) -> Int {
    let covered = active.union(frozen).sorted()
    var best = 0
    var run = 0
    var previous: DayKey?
    for day in covered {
      if let previous, previous.adding(days: 1, calendar: calendar) == day {
        // continues the run
      } else {
        run = 0
      }
      if active.contains(day) { run += 1 }
      best = max(best, run)
      previous = day
    }
    return best
  }

  /// The gap days (strictly between the last covered day and today) to freeze, or `[]` when
  /// there is no gap, the gap is larger than `available`, or no streak would be saved.
  public static func freezePlan(
    active: Set<DayKey>, frozen: Set<DayKey>, today: DayKey,
    available: Int, calendar: Calendar
  ) -> [DayKey] {
    let covered = active.union(frozen)
    guard let last = covered.filter({ $0 <= today }).max() else { return [] }
    var gap: [DayKey] = []
    var day = last.adding(days: 1, calendar: calendar)
    while day < today {
      gap.append(day)
      day = day.adding(days: 1, calendar: calendar)
    }
    guard !gap.isEmpty, gap.count <= available else { return [] }
    let streakAtLast = current(active: active, frozen: frozen, today: last, calendar: calendar)
    return streakAtLast > 0 ? gap : []
  }
}
