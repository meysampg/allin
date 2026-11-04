import Foundation
import SwiftData
import Testing

@testable import AllInStore

@MainActor
@Suite struct ProgressStoreTests {
  func makeStore() throws -> ProgressStore {
    ProgressStore(container: try AllInPersistence.makeContainer(inMemory: true))
  }

  @Test func defaultProfileCreatedOnce() throws {
    let store = try makeStore()
    let first = store.profile()
    #expect(first.name == "Traveler" && first.gold == 200 && first.rank == "Tavern Regular")
    let second = store.profile()
    #expect(second == first)
    let count = try store.container.mainContext.fetchCount(FetchDescriptor<AllInSchemaV1.ProfileEntity>())
    #expect(count == 1)
  }

  @Test func updateProfile() throws {
    let store = try makeStore()
    store.updateProfile {
      $0.name = "Ada"
      $0.gold += 50
      $0.streakDays = 3
    }
    let p = store.profile()
    #expect(p.name == "Ada" && p.gold == 250 && p.streakDays == 3)
  }

  @Test func sessionBeginEnd() throws {
    let store = try makeStore()
    let start = Date(timeIntervalSinceReferenceDate: 500)
    let id = store.beginSession(kind: .career, format: "6-max", startedAt: start)
    #expect(store.session(id)?.endedAt == nil)
    let end = Date(timeIntervalSinceReferenceDate: 900)
    store.endSession(
      id, at: end, totals: SessionTotals(hands: 12, decisionScore: 80, netChips: 300, luckChips: 10.5, assisted: true))
    let s = try #require(store.session(id))
    #expect(s.kind == .career && s.format == "6-max" && s.startedAt == start && s.endedAt == end)
    #expect(s.hands == 12 && s.decisionScore == 80 && s.netChips == 300 && s.luckChips == 10.5 && s.assisted)
    let later = store.beginSession(kind: .quick, format: "hu", startedAt: Date(timeIntervalSinceReferenceDate: 600))
    #expect(store.sessions().map(\.id) == [later, id])
    #expect(store.session(UUID()) == nil)
  }

  @Test func upsertEachEntity() throws {
    let store = try makeStore()
    let t = Date(timeIntervalSinceReferenceDate: 42)
    for round in 1...2 {
      store.upsert(StoredSkillState(skillID: "s", theta: Double(round), evidence: 2, updatedAt: t))
      store.upsert(
        StoredDecisionCard(
          key: "c", stateRaw: round, stability: 1.5, difficulty: 2.5, due: t, lastReview: t, reps: round, lapses: 0,
          instanceHashes: ["a", "b"]))
      store.upsert(StoredNodeProgress(nodeID: "n", statusRaw: "open", stars: round, bestScore: 0.5))
      store.upsert(StoredRivalKnowledge(characterID: "r", handsPlayed: round, statsJSON: Data([9]), autoNotes: ["x"]))
      store.upsert(StoredPlayerModelSnapshot(id: "m", version: round, blob: Data([1]), updatedAt: t))
      store.unlock("gold-chip", at: t)
      store.saveSpot(
        StoredSavedSpot(
          key: "k", handKey: "h", decisionIndex: round, streetRaw: "flop", title: "Spot \(round)", createdAt: t))
    }
    #expect(store.skillState("s")?.theta == 2)
    #expect(store.decisionCard("c")?.reps == 2)
    #expect(store.decisionCard("c")?.instanceHashes == ["a", "b"])
    #expect(store.nodeProgress("n")?.stars == 2)
    #expect(store.rival("r")?.handsPlayed == 2)
    #expect(store.rival("r")?.autoNotes == ["x"])
    #expect(store.playerModel("m")?.version == 2)
    #expect(store.unlocks().count == 1)
    #expect(store.savedSpots().count == 1)
    #expect(store.savedSpots().first?.title == "Spot 2")
    #expect(store.skillState("none") == nil)
  }

  @Test func revisionBumps() throws {
    let store = try makeStore()
    let r0 = store.revision
    _ = store.profile()
    #expect(store.revision > r0)
    let r1 = store.revision
    store.unlock("x")
    #expect(store.revision > r1)
  }
}
