import Foundation
import PokerAnalysis
import Testing

@testable import Curriculum

@Suite struct DrillSchedulerTests {
  let cal = SRSTestSupport.utc
  let now = SRSTestSupport.t0
  var ds: DrillScheduler { DrillScheduler(scheduler: FSRSScheduler(calendar: cal)) }

  func entry(_ t: String, _ s: String, _ o: Int) -> DrillPool.Entry { .init(templateID: t, skill: s, order: o) }

  var pool: DrillPool {
    DrillPool(
      entries: [
        entry("t.a1", "a", 0), entry("t.a2", "a", 1), entry("t.b1", "b", 2), entry("t.c1", "c", 3),
        entry("t.d1", "d", 4), entry("t.e1", "e", 5),
      ],
      baseDifficulty: ["a": 0.4, "b": 0.4, "c": 0.4, "d": 0.4, "e": 0.4])
  }

  func skills(_ meters: [String: Double]) -> SkillModel {
    var m = SkillModel()
    for (s, v) in meters {
      m.ratings[s] = SkillRating(theta: SkillModel.theta(forMeter: v, baseDifficulty: 0.4), evidence: 3, updatedAt: now)
    }
    return m
  }

  func card(_ t: String, _ cls: String, due: TimeInterval) -> DecisionCardState {
    var c = FSRSCard.new(now: now)
    c.due = now.addingTimeInterval(due)
    return DecisionCardState(key: DecisionTypeKey(templateID: t, answerClass: cls), card: c)
  }

  @Test func dueCardsFirstInDueOrder() {
    let cards = [card("t.b1", "x", due: -10), card("t.a1", "y", due: -100), card("t.c1", "z", due: -10)]
    let picks = ds.smartMix(count: 5, pool: pool, skills: SkillModel(), cards: cards, now: now, seed: 1)
    #expect(picks.prefix(3).map(\.templateID) == ["t.a1", "t.b1", "t.c1"])
    #expect(picks[0].targetAnswerClass == "y")
    #expect(picks[0].reason == .due(DecisionTypeKey(templateID: "t.a1", answerClass: "y")))
    #expect(picks.count == 5)
  }

  @Test func notYetDueAndOutOfPoolExcluded() {
    let cards = [card("t.a1", "y", due: 3600), card("t.zzz", "y", due: -5)]
    let picks = ds.smartMix(count: 3, pool: pool, skills: SkillModel(), cards: cards, now: now, seed: 1)
    for p in picks {
      if case .due = p.reason { Issue.record("unexpected due pick") }
    }
  }

  @Test func weakBeforeNewAlternating() {
    let m = skills(["a": 0.5, "b": 0.2])
    let picks = ds.smartMix(count: 6, pool: pool, skills: m, cards: [], now: now, seed: 9)
    #expect(picks.map(\.skill) == ["b", "c", "a", "d", "b", "e"])
    #expect(picks[0].reason == .weakSkill("b"))
    #expect(picks[1].reason == .newMaterial("c"))
    #expect(picks.allSatisfy { $0.targetAnswerClass == nil })
  }

  @Test func masteredSkillsAreSkipped() {
    var m = skills(["a": 0.5])
    m.ratings["b"] = SkillRating(theta: 5, evidence: 20, updatedAt: now)
    let picks = ds.smartMix(count: 8, pool: pool, skills: m, cards: [], now: now, seed: 2)
    #expect(!picks.contains { $0.skill == "b" })
  }

  @Test func deterministicAndCountRespected() {
    let m = skills(["a": 0.3])
    let one = ds.smartMix(count: 7, pool: pool, skills: m, cards: [], now: now, seed: 5)
    let two = ds.smartMix(count: 7, pool: pool, skills: m, cards: [], now: now, seed: 5)
    #expect(one == two)
    #expect(one.count == 7)
    #expect(ds.smartMix(count: 0, pool: pool, skills: m, cards: [], now: now, seed: 5).isEmpty)
    #expect(ds.warmUp(pool: pool, skills: m, cards: [], now: now, seed: 5).count == 10)
    let seeds = Set(
      (0..<20).map { ds.smartMix(count: 1, pool: pool, skills: m, cards: [], now: now, seed: UInt64($0))[0].templateID }
    )
    #expect(seeds == ["t.a1", "t.a2"])
  }

  @Test func ratingMapping() {
    #expect(DrillScheduler.rating(grade: .leak, fast: true, usedHint: false) == .again)
    #expect(DrillScheduler.rating(grade: .smallMiss, fast: true, usedHint: false) == .hard)
    #expect(DrillScheduler.rating(grade: .good, fast: false, usedHint: false) == .good)
    #expect(DrillScheduler.rating(grade: .good, fast: true, usedHint: true) == .good)
    #expect(DrillScheduler.rating(grade: .good, fast: true, usedHint: false) == .easy)
  }

  @Test func reviewAppendsAndPrunesRecent() {
    let key = DecisionTypeKey(templateID: "t.a1", answerClass: "x")
    let first = ds.review(nil, key: key, grade: .good, fast: false, usedHint: false, instanceHash: "h1", now: now)
    #expect(first.card.reps == 1 && first.card.state == .review)
    #expect(first.recent.map(\.hash) == ["h1"])
    let day61 = cal.date(byAdding: .day, value: 61, to: now)!
    let second = ds.review(first, key: key, grade: .leak, fast: false, usedHint: false, instanceHash: "h2", now: day61)
    #expect(second.recent.map(\.hash) == ["h2"])
    #expect(second.card.lapses == 1)
    let day30 = cal.date(byAdding: .day, value: 30, to: now)!
    let third = ds.review(first, key: key, grade: .good, fast: false, usedHint: false, instanceHash: "h3", now: day30)
    #expect(third.recent.map(\.hash) == ["h1", "h3"])
  }

  @Test func avoidSetWindow() {
    let key = DecisionTypeKey(templateID: "t", answerClass: "x")
    let today = DayKey(now, calendar: cal)
    let cardState = DecisionCardState(
      key: key, card: .new(now: now),
      recent: [
        RecentInstance(hash: "old", day: today.adding(days: -61, calendar: cal)),
        RecentInstance(hash: "edge", day: today.adding(days: -60, calendar: cal)),
        RecentInstance(hash: "new", day: today),
      ])
    #expect(DrillScheduler.avoidSet([cardState], now: now, calendar: cal) == ["edge", "new"])
  }

  @Test func recentInstanceRawValue() {
    let r = RecentInstance(hash: "abc", day: DayKey(year: 2026, month: 1, day: 2))
    #expect(r.rawValue == "abc|2026-01-02")
    #expect(RecentInstance(rawValue: r.rawValue) == r)
    #expect(RecentInstance(rawValue: "nobar") == nil)
  }
}
