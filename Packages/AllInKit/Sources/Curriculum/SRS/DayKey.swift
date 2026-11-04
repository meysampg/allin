// Ported from Kata (KataKit/Sources/KataSRS/DayKey.swift); arithmetic unchanged.
import Foundation

/// A calendar day without a time zone: `yyyy-MM-dd` in the calendar the caller passes in.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// The caller passes `DayKey.gregorian(timeZone:)` so keys stay in the stored gregorian format.
  public init(_ date: Date, calendar: Calendar) {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
  }

  public init?(string: String) {
    let parts = string.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
      (1...12).contains(m), (1...31).contains(d)
    else { return nil }
    self.init(year: y, month: m, day: d)
  }

  public var string: String { String(format: "%04d-%02d-%02d", year, month, day) }
  public var description: String { string }

  public func startDate(in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
  }

  /// Goes through noon so a DST change never shifts the result by a day.
  public func adding(days: Int, calendar: Calendar) -> DayKey {
    let noon =
      calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? startDate(in: calendar)
    let moved = calendar.date(byAdding: .day, value: days, to: noon) ?? noon
    return DayKey(moved, calendar: calendar)
  }

  public static func gregorian(timeZone: TimeZone = .current) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = timeZone
    return c
  }

  public static func < (l: DayKey, r: DayKey) -> Bool {
    (l.year, l.month, l.day) < (r.year, r.month, r.day)
  }
}
