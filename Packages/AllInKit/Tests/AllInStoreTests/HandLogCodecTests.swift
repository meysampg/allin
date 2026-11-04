import Foundation
import Testing

@testable import AllInStore

@Suite struct HandLogCodecTests {
  @Test func roundTripsHostLog() throws {
    let log = try StoreFixtures.log()
    let data = try HandLogCodec.encode(log)
    #expect(try HandLogCodec.decode(data) == log)
  }

  @Test func compresses() throws {
    let log = try StoreFixtures.log()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let raw = try encoder.encode(log)
    let data = try HandLogCodec.encode(log)
    #expect(data.count < raw.count)
  }
}
