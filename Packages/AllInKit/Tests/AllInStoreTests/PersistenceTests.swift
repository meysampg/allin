import Foundation
import Testing

@testable import AllInStore

@MainActor
@Suite struct PersistenceTests {
  @Test func fileStoreReopens() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("allin.store")
    let session = UUID()
    let input = try StoreFixtures.input(session: session, hand: 3)
    do {
      let archive = HandArchive(container: try AllInPersistence.makeContainer(url: url))
      try archive.save(input)
    }
    let reopened = HandArchive(container: try AllInPersistence.makeContainer(url: url))
    #expect(reopened.count() == 1)
    #expect(try reopened.hand(input.key)?.log == input.log)
  }
}
