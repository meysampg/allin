import Foundation
import PokerCore
import SwiftData
import Testing

@testable import AllInStore

@MainActor
@Suite struct HandArchiveTests {
  func makeArchive() throws -> HandArchive {
    HandArchive(container: try AllInPersistence.makeContainer(inMemory: true))
  }

  @Test func saveAndLoad() throws {
    let archive = try makeArchive()
    let session = UUID()
    let input = try StoreFixtures.input(session: session, hand: 5)
    try archive.save(input)
    let loaded = try #require(try archive.hand(input.key))
    #expect(loaded.log == input.log)
    #expect(loaded.seats == input.seats)
    #expect(loaded.strategySeed == input.strategySeed)
    #expect(loaded.netChips == -150 && loaded.potTotal == 400 && loaded.bigBlind == 100)
    #expect(loaded.playedAt == input.playedAt)
    #expect(loaded.grades == nil && loaded.analysis == nil)
    #expect(try archive.hand(ArchiveKey(sessionID: session, handID: 99)) == nil)
  }

  @Test func upsertKeepsOneRow() throws {
    let archive = try makeArchive()
    let session = UUID()
    var input = try StoreFixtures.input(session: session, hand: 1)
    try archive.save(input)
    input.netChips = 500
    try archive.save(input)
    #expect(archive.count() == 1)
    #expect(try archive.hand(input.key)?.netChips == 500)
  }

  @Test func attachAnalysisMarksGraded() throws {
    let archive = try makeArchive()
    let input = try StoreFixtures.input(session: UUID(), hand: 1)
    try archive.save(input)
    let blob = Data([1, 2, 3])
    try archive.attachAnalysis(input.key, analysis: blob, grades: StoreFixtures.grades)
    let loaded = try #require(try archive.hand(input.key))
    #expect(loaded.analysis == blob)
    #expect(loaded.grades == StoreFixtures.grades)
    #expect(archive.summaries().first?.grades == StoreFixtures.grades)
    // Saving again resets the grade.
    try archive.save(input)
    #expect(try archive.hand(input.key)?.grades == nil)
  }

  @Test func latestAndSummariesAreNewestFirst() throws {
    let archive = try makeArchive()
    let session = UUID()
    for i in 1...4 {
      try archive.save(
        StoreFixtures.input(
          session: session, hand: UInt64(i), at: Date(timeIntervalSinceReferenceDate: Double(i * 100))))
    }
    let summaries = archive.summaries()
    #expect(summaries.map(\.key.handID.rawValue) == [4, 3, 2, 1])
    #expect(archive.summaries(limit: 2).count == 2)
    #expect(try archive.latest()?.key.handID.rawValue == 4)
    #expect(try archive.latest(sessionID: UUID()) == nil)
    #expect(try archive.latest(sessionID: session)?.key.handID.rawValue == 4)
  }

  @Test func countBySession() throws {
    let archive = try makeArchive()
    let a = UUID()
    let b = UUID()
    try archive.save(StoreFixtures.input(session: a, hand: 1))
    try archive.save(StoreFixtures.input(session: a, hand: 2))
    try archive.save(StoreFixtures.input(session: b, hand: 1))
    #expect(archive.count() == 3)
    #expect(archive.count(sessionID: a) == 2)
    #expect(archive.count(sessionID: b) == 1)
    #expect(archive.summaries(sessionID: a).count == 2)
  }

  @Test func keyRawValueRoundTrip() {
    let key = ArchiveKey(sessionID: UUID(), handID: HandID(UInt64.max))
    #expect(ArchiveKey(rawValue: key.rawValue) == key)
    #expect(ArchiveKey(rawValue: "nonsense") == nil)
    #expect(ArchiveKey(rawValue: "\(UUID().uuidString)#x") == nil)
  }
}
