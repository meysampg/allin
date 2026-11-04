import Foundation
import Testing

@testable import Curriculum

@Suite struct StreakCalculatorTests {
  let cal = DayKey.gregorian(timeZone: TimeZone(identifier: "UTC")!)
  let today = DayKey(year: 2026, month: 4, day: 10)

  func d(_ ago: Int) -> DayKey { today.adding(days: -ago, calendar: cal) }
  func set(_ ago: [Int]) -> Set<DayKey> { Set(ago.map(d)) }
  func current(_ a: [Int], _ f: [Int] = []) -> Int {
    StreakCalculator.current(active: set(a), frozen: set(f), today: today, calendar: cal)
  }

  @Test func currentBasics() {
    #expect(current([]) == 0)
    #expect(current([0]) == 1)
    #expect(current([0, 1, 2]) == 3)
    #expect(current([1, 2]) == 2)  // yesterday continuation
    #expect(current([2, 3]) == 0)  // missed yesterday
    #expect(current([0, 1, 3]) == 2)  // a gap breaks the streak
  }

  @Test func frozenBridgesWithoutCounting() {
    #expect(current([0, 1, 3, 4], [2]) == 4)
    #expect(current([0, 2, 3], [1]) == 3)
    #expect(current([1, 3], [2]) == 2)
    #expect(current([], [1]) == 0)
  }

  @Test func longest() {
    func longest(_ a: [Int], _ f: [Int] = []) -> Int {
      StreakCalculator.longest(active: set(a), frozen: set(f), calendar: cal)
    }
    #expect(longest([]) == 0)
    #expect(longest([5]) == 1)
    #expect(longest([0, 1, 2, 10, 11, 12, 13]) == 4)
    #expect(longest([0, 1, 3, 4, 5], [2]) == 5)
    #expect(longest([0, 1, 3, 4, 5]) == 3)
    #expect(longest([], [3, 4]) == 0)
  }

  @Test func freezePlan() {
    func plan(_ a: [Int], _ f: [Int] = [], available: Int) -> [DayKey] {
      StreakCalculator.freezePlan(active: set(a), frozen: set(f), today: today, available: available, calendar: cal)
    }
    #expect(plan([2, 3], available: 1) == [d(1)])
    #expect(plan([3, 4], available: 1).isEmpty)  // gap 2, one freeze
    #expect(plan([3, 4], available: 2) == [d(2), d(1)])
    #expect(plan([], available: 2).isEmpty)  // no history
    #expect(plan([0, 1], available: 2).isEmpty)  // no gap
    #expect(plan([1], available: 0).isEmpty)
    #expect(plan([], [3], available: 2).isEmpty)  // nothing to save
    #expect(plan([3, 4], [2], available: 1) == [d(1)])  // extends over an earlier freeze
  }
}
