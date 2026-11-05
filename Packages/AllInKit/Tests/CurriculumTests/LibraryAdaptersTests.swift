import Foundation
import Testing

@testable import Curriculum

@Suite struct LibraryAdaptersTests {
  private let library = CurriculumTestSupport.fixture

  @Test func poolFollowsNodeOrderAndDedupes() {
    let pool = library.drillPool(unlockedVenues: ["fx.tavern"])
    let ids = pool.entries.map(\.templateID)
    #expect(!ids.isEmpty)
    #expect(Set(ids).count == ids.count)
    #expect(pool.entries.map(\.order) == Array(0..<ids.count))
    // The first node's lesson comes first.
    let firstLesson = library.lesson(library.venues[0].nodes[0].lesson ?? "")
    let firstSpot = firstLesson?.steps.compactMap(\.spotID).first
    #expect(ids.first == firstSpot)
    for entry in pool.entries { #expect(library.template(entry.templateID)?.skill == entry.skill) }
    #expect(pool.baseDifficulty == library.skills.baseDifficulties)
  }

  @Test func poolIgnoresUnknownAndLockedVenues() {
    #expect(library.drillPool(unlockedVenues: []).entries.isEmpty)
    #expect(library.drillPool(unlockedVenues: ["fx.guild", "nope"]).entries.isEmpty)
    let once = library.drillPool(unlockedVenues: ["fx.tavern"])
    let twice = library.drillPool(unlockedVenues: ["fx.tavern", "fx.tavern"])
    #expect(once == twice)
  }

  @Test func meterValueIsTheGroupMean() throws {
    let meter = try #require(library.venues[0].meters.first)
    #expect(library.meterValue(meter, skills: SkillModel()) == 0)
    var model = SkillModel()
    let base = library.skills.baseDifficulties
    for skill in meter.skills {
      let theta = SkillModel.theta(forMeter: 0.8, baseDifficulty: base[skill] ?? 0.5)
      model.ratings[skill] = SkillRating(theta: theta, evidence: 10, updatedAt: nil)
    }
    #expect(abs(library.meterValue(meter, skills: model) - 0.8) < 1e-6)
  }

  @Test func storedCardRoundTrips() throws {
    let day = try #require(DayKey(string: "2026-03-14"))
    let state = DecisionCardState(
      key: DecisionTypeKey(templateID: "fx.spot.a", answerClass: "call"),
      card: FSRSCard(
        stability: 3.5, difficulty: 6.25, due: Date(timeIntervalSince1970: 1_000_000),
        lastReview: Date(timeIntervalSince1970: 900_000), reps: 4, lapses: 1, state: .review),
      recent: [RecentInstance(hash: "abc123", day: day)])
    let back = try #require(
      DecisionCardState(
        stored: state.key.rawValue, stateRaw: state.card.state.rawValue, stability: state.card.stability,
        difficulty: state.card.difficulty, due: state.card.due, lastReview: state.card.lastReview,
        reps: state.card.reps, lapses: state.card.lapses, instanceHashes: state.instanceHashStrings))
    #expect(back == state)
    #expect(state.instanceHashStrings == ["abc123|2026-03-14"])
  }

  @Test func storedCardRejectsBadKeyAndDropsBadHashes() throws {
    let due = Date(timeIntervalSince1970: 0)
    #expect(
      DecisionCardState(
        stored: "no-hash", stateRaw: 0, stability: 0, difficulty: 0, due: due, lastReview: nil, reps: 0, lapses: 0,
        instanceHashes: []) == nil)
    let state = try #require(
      DecisionCardState(
        stored: "t#c", stateRaw: 99, stability: 0, difficulty: 0, due: due, lastReview: nil, reps: 0, lapses: 0,
        instanceHashes: ["garbage", "h|2026-01-02"]))
    #expect(state.card.state == .new)
    #expect(state.recent.count == 1)
  }
}
