import Foundation
import Testing

@testable import Curriculum

@Suite struct UnlockResolverTests {
  private let library = CurriculumTestSupport.fixture
  private var venue: Venue { library.venues[0] }

  private func progress(_ done: [String], stars: [String: Int] = [:]) -> ProgressSnapshot {
    ProgressSnapshot(
      nodes: Dictionary(
        uniqueKeysWithValues: done.map { ($0, NodeRecord(nodeID: $0, completed: true, stars: stars[$0] ?? 1)) }))
  }

  private func status(_ id: String, _ p: ProgressSnapshot) -> NodeStatus {
    UnlockResolver.status(of: venue.node(id)!, in: venue, library: library, progress: p)
  }

  @Test func defaultChain() {
    let none = ProgressSnapshot()
    #expect(status("fx.tavern.n1", none) == .available)
    #expect(status("fx.tavern.n2", none) == .locked)
    let one = progress(["fx.tavern.n1"])
    #expect(status("fx.tavern.n1", one) == .completed)
    #expect(status("fx.tavern.n2", one) == .available)
    #expect(status("fx.tavern.n3", one) == .locked)
    #expect(UnlockResolver.currentNode(in: venue, library: library, progress: one)?.id == "fx.tavern.n2")
    #expect(UnlockResolver.currentNode(in: venue, library: library, progress: none)?.id == "fx.tavern.n1")
  }

  @Test func explicitAfter() {
    #expect(status("fx.tavern.n7", progress(["fx.tavern.n1", "fx.tavern.n2", "fx.tavern.n3"])) == .locked)
    #expect(status("fx.tavern.n7", progress(["fx.tavern.n6"])) == .available)
    #expect(venue.prerequisites(of: venue.node("fx.tavern.n7")!) == ["fx.tavern.n6"])
    #expect(venue.prerequisites(of: venue.node("fx.tavern.n1")!).isEmpty)
  }

  private let allButBoss = [
    "fx.tavern.n1", "fx.tavern.n2", "fx.tavern.n3", "fx.tavern.n4", "fx.tavern.n5", "fx.tavern.n6",
  ]

  @Test func venueStatuses() {
    let tavern = library.realmVenue("fx.tavern")!
    let guild = library.realmVenue("fx.guild")!
    let keep = library.realmVenue("fx.keep")!
    #expect(
      UnlockResolver.status(of: tavern, library: library, progress: ProgressSnapshot()) == .open(completed: 0, total: 7)
    )
    #expect(
      UnlockResolver.status(of: tavern, library: library, progress: progress(allButBoss))
        == .open(completed: 6, total: 7))
    #expect(UnlockResolver.status(of: guild, library: library, progress: ProgressSnapshot()) == .comingSoon)
    #expect(UnlockResolver.status(of: keep, library: library, progress: ProgressSnapshot()) == .comingSoon)
    let cleared = progress(allButBoss + ["fx.tavern.n7"], stars: ["fx.tavern.n7": 3])
    #expect(UnlockResolver.status(of: tavern, library: library, progress: cleared) == .cleared(stars: 3))
    #expect(UnlockResolver.isCleared(venue, progress: cleared))
    #expect(!UnlockResolver.isCleared(venue, progress: progress(allButBoss)))
  }

  @Test func lockedVenueReasonAndCurrent() throws {
    // Make the guild open in a mutated pack, with a venue folder for it.
    var files = CurriculumTestSupport.mutate(file: "realm.json") {
      var venues = $0["venues"] as! [[String: Any]]
      venues[1]["status"] = "open"
      $0["venues"] = venues
    }
    var guild = try #require(
      JSONSerialization.jsonObject(with: files["\(CurriculumTestSupport.tavern)venue.json"]!) as? [String: Any])
    guild["id"] = "fx.guild"
    guild["name"] = "Guild Hall"
    guild["nodes"] = [["id": "fx.guild.n1", "kind": "lesson", "lesson": "fx.tavern.l1.four-rounds"]]
    guild["meters"] = []
    files["venues/fx.guild/venue.json"] = try JSONSerialization.data(withJSONObject: guild)
    let two = try ContentLibrary.load(files: files, characters: CurriculumTestSupport.catalog)
    let entry = two.realmVenue("fx.guild")!
    #expect(
      UnlockResolver.status(of: entry, library: two, progress: ProgressSnapshot())
        == .locked(reason: "beat the Tavern boss"))
    #expect(UnlockResolver.currentVenue(library: two, progress: ProgressSnapshot())?.id == "fx.tavern")
    #expect(UnlockResolver.unlockedVenueIDs(library: two, progress: ProgressSnapshot()) == ["fx.tavern"])
    let done = progress(allButBoss + ["fx.tavern.n7"])
    #expect(UnlockResolver.currentVenue(library: two, progress: done)?.id == "fx.guild")
    #expect(UnlockResolver.unlockedVenueIDs(library: two, progress: done) == ["fx.tavern", "fx.guild"])
    let guildVenue = two.venue("fx.guild")!
    #expect(
      UnlockResolver.status(of: guildVenue.nodes[0], in: guildVenue, library: two, progress: ProgressSnapshot())
        == .locked)
    #expect(UnlockResolver.status(of: guildVenue.nodes[0], in: guildVenue, library: two, progress: done) == .available)
  }

  @Test func currentVenueOfFixture() {
    #expect(UnlockResolver.currentVenue(library: library, progress: ProgressSnapshot())?.id == "fx.tavern")
    #expect(UnlockResolver.unlockedVenueIDs(library: library, progress: ProgressSnapshot()) == ["fx.tavern"])
  }
}
