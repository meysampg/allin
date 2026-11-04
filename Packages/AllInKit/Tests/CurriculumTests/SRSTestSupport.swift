// Ported from Kata (KataSRSTests/MemorizationTestSupport.swift).
import Foundation

@testable import Curriculum

enum SRSTestSupport {
  static var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
}
