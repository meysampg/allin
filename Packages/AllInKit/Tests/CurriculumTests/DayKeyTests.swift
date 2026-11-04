import Foundation
import Testing

@testable import Curriculum

@Suite struct DayKeyTests {
  let utc = DayKey.gregorian(timeZone: TimeZone(identifier: "UTC")!)

  @Test func stringRoundTrip() {
    let k = DayKey(year: 2026, month: 4, day: 9)
    #expect(k.string == "2026-04-09")
    #expect(DayKey(string: k.string) == k)
    #expect(DayKey(string: "2026-4-09") == nil)
    #expect(DayKey(string: "2026-13-01") == nil)
    #expect(DayKey(string: "garbage") == nil)
  }

  @Test func addingCrossesMonthAndYear() {
    #expect(
      DayKey(year: 2026, month: 12, day: 31).adding(days: 1, calendar: utc) == DayKey(year: 2027, month: 1, day: 1))
    #expect(
      DayKey(year: 2026, month: 3, day: 1).adding(days: -1, calendar: utc) == DayKey(year: 2026, month: 2, day: 28))
  }

  @Test func addingIsDSTSafe() {
    var ny = Calendar(identifier: .gregorian)
    ny.timeZone = TimeZone(identifier: "America/New_York")!
    // US spring forward 2026-03-08, fall back 2026-11-01.
    #expect(DayKey(year: 2026, month: 3, day: 7).adding(days: 1, calendar: ny) == DayKey(year: 2026, month: 3, day: 8))
    #expect(DayKey(year: 2026, month: 3, day: 8).adding(days: 1, calendar: ny) == DayKey(year: 2026, month: 3, day: 9))
    #expect(
      DayKey(year: 2026, month: 11, day: 1).adding(days: 1, calendar: ny) == DayKey(year: 2026, month: 11, day: 2))
    #expect(
      DayKey(year: 2026, month: 11, day: 2).adding(days: -1, calendar: ny) == DayKey(year: 2026, month: 11, day: 1))
  }

  @Test func comparableAndCodable() throws {
    #expect(DayKey(year: 2026, month: 1, day: 31) < DayKey(year: 2026, month: 2, day: 1))
    let k = DayKey(year: 2026, month: 4, day: 9)
    let data = try JSONEncoder().encode(k)
    #expect(try JSONDecoder().decode(DayKey.self, from: data) == k)
  }
}
