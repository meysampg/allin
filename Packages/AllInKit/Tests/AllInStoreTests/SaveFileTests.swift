import Foundation
import Testing

@testable import AllInStore

@MainActor
@Suite struct SaveFileTests {
  func filledStore() throws -> (ProgressStore, HandArchive) {
    let container = try AllInPersistence.makeContainer(inMemory: true)
    let store = ProgressStore(container: container)
    let archive = HandArchive(container: container)
    let t = Date(timeIntervalSinceReferenceDate: 12_345.678)
    store.updateProfile { $0.name = "Ada" }
    store.upsert(StoredSkillState(skillID: "s", theta: 0.1, evidence: 3, updatedAt: t))
    store.upsert(
      StoredDecisionCard(
        key: "c", stateRaw: 2, stability: 1.25, difficulty: 3.5, due: t, lastReview: t, reps: 4, lapses: 1,
        instanceHashes: ["h1"]))
    store.upsert(StoredNodeProgress(nodeID: "n", statusRaw: "done", stars: 3, bestScore: 0.9))
    store.upsert(StoredRivalKnowledge(characterID: "r", handsPlayed: 9, statsJSON: Data([1, 2]), notes: "tight"))
    store.upsert(StoredPlayerModelSnapshot(id: "m", version: 1, blob: Data([5, 6]), updatedAt: t))
    store.unlock("chip", at: t)
    store.saveSpot(
      StoredSavedSpot(key: "k", handKey: "h", decisionIndex: 2, streetRaw: "turn", title: "T", createdAt: t))
    let session = store.beginSession(kind: .quick, format: "6-max", startedAt: t)
    store.endSession(session, at: t, totals: SessionTotals(hands: 2, decisionScore: 70, netChips: 10, luckChips: 1.5))
    for i in 1...2 {
      let input = try StoreFixtures.input(session: session, hand: UInt64(i), at: t.addingTimeInterval(Double(i)))
      try archive.save(input)
    }
    try archive.attachAnalysis(
      ArchiveKey(sessionID: session, handID: 1), analysis: Data([7, 7]), grades: StoreFixtures.grades)
    return (store, archive)
  }

  @Test func exportImportRoundTrip() throws {
    let (store, _) = try filledStore()
    let now = Date(timeIntervalSinceReferenceDate: 99)
    let exported = store.exportSaveFile(now: now)
    #expect(exported.hands.count == 2 && exported.sessions.count == 1)
    let data = try SaveFileCodec.encode(exported)

    let fresh = ProgressStore(container: try AllInPersistence.makeContainer(inMemory: true))
    fresh.unlock("stale")
    try fresh.importSaveFile(try SaveFileCodec.decode(data))
    var again = fresh.exportSaveFile(now: now)
    #expect(again == exported)
    again.exportedAt = Date(timeIntervalSinceReferenceDate: 1)
    var original = exported
    original.exportedAt = again.exportedAt
    #expect(again == original)
    #expect(fresh.unlocks().map(\.rewardID) == ["chip"])
    let archive = HandArchive(container: fresh.container)
    #expect(archive.count() == 2)
  }

  @Test func rejectsNewerVersion() throws {
    let (store, _) = try filledStore()
    var file = store.exportSaveFile()
    file.schemaVersion = SaveFile.currentVersion + 1
    let data = try SaveFileCodec.encode(file)
    #expect(throws: SaveFileError.unsupportedVersion(SaveFile.currentVersion + 1)) {
      try SaveFileCodec.decode(data)
    }
    #expect(throws: SaveFileError.unsupportedVersion(SaveFile.currentVersion + 1)) {
      try store.importSaveFile(file)
    }
    #expect(throws: SaveFileError.self) { try SaveFileCodec.decode(Data("nope".utf8)) }
  }

  @Test func decodeEncodeIsStable() throws {
    let (store, _) = try filledStore()
    let data = try SaveFileCodec.encode(store.exportSaveFile(now: Date(timeIntervalSinceReferenceDate: 5)))
    let decoded = try SaveFileCodec.decode(data)
    #expect(try SaveFileCodec.encode(decoded) == data)
  }
}
