import Foundation
import Testing

@testable import Curriculum

@Suite struct FSRSSchedulerTests {
  let cal = SRSTestSupport.utc
  let now = SRSTestSupport.t0
  var sch: FSRSScheduler { FSRSScheduler(calendar: cal) }

  func close(_ a: Double, _ b: Double, _ tol: Double = 1e-3) -> Bool { abs(a - b) < tol }

  func days(_ r: SchedulingResult, from d: Date) -> Int {
    cal.dateComponents([.day], from: d, to: r.card.due).day ?? -1
  }

  @Test func newCardVectors() {
    let c = FSRSCard.new(now: now)
    let again = sch.next(c, rating: .again, now: now)
    #expect(close(again.card.stability, 0.40255) && close(again.card.difficulty, 7.1949))
    #expect(again.card.state == .learning)
    #expect(again.card.due == now.addingTimeInterval(600))
    #expect(again.scheduledDays == 0)

    let hard = sch.next(c, rating: .hard, now: now)
    #expect(close(hard.card.stability, 1.18385) && close(hard.card.difficulty, 6.4883))
    #expect(days(hard, from: now) == 1)
    let good = sch.next(c, rating: .good, now: now)
    #expect(close(good.card.stability, 3.173) && close(good.card.difficulty, 5.2824))
    #expect(days(good, from: now) == 3 && good.card.state == .review)
    let easy = sch.next(c, rating: .easy, now: now)
    #expect(close(easy.card.stability, 15.69105) && close(easy.card.difficulty, 3.2245))
    #expect(days(easy, from: now) == 16)
    #expect(easy.card.reps == 1 && easy.card.lastReview == now)
  }

  func goodCard() -> (FSRSCard, Date) {
    let c = FSRSCard.new(now: now)
    let g = sch.next(c, rating: .good, now: now).card
    return (g, cal.date(byAdding: .day, value: 3, to: now)!)
  }

  @Test func reviewAfterThreeDays() {
    let (card, later) = goodCard()
    #expect(close(sch.retrievability(card, at: later), 0.9047))
    let hard = sch.next(card, rating: .hard, now: later)
    #expect(close(hard.card.stability, 4.9245) && close(hard.card.difficulty, 6.0350))
    #expect(days(hard, from: later) == 5)
    let good = sch.next(card, rating: .good, now: later)
    #expect(close(good.card.stability, 10.7389) && close(good.card.difficulty, 5.2730))
    #expect(days(good, from: later) == 11)
    let easy = sch.next(card, rating: .easy, now: later)
    #expect(close(easy.card.stability, 25.7936) && close(easy.card.difficulty, 4.5110))
    #expect(days(easy, from: later) == 26)
    let again = sch.next(card, rating: .again, now: later)
    #expect(close(again.card.stability, 1.0556) && close(again.card.difficulty, 6.7969))
    #expect(again.card.lapses == 1 && again.card.state == .relearning)
    #expect(again.card.due == later.addingTimeInterval(600))
    #expect(again.elapsedDays == 3)
  }

  @Test func shortTermGood() {
    let (card, _) = goodCard()
    let later = now.addingTimeInterval(3600)
    let r = sch.next(card, rating: .good, now: later)
    #expect(close(r.card.stability, 4.4669))
    #expect(r.card.state == .review)
  }

  @Test func intervalOrdering() {
    let (card, later) = goodCard()
    for (c, d) in [(FSRSCard.new(now: now), now), (card, later)] {
      let p = sch.preview(c, now: d)
      let h = p[.hard]!.scheduledDays, g = p[.good]!.scheduledDays, e = p[.easy]!.scheduledDays
      #expect(h < g && g < e)
    }
  }

  @Test func orderingForcedWhenIntervalsCollide() {
    // Tiny stability: raw intervals would all be 1 day.
    let c = FSRSCard(stability: 0.05, difficulty: 5, due: now, lastReview: now, reps: 3, lapses: 0, state: .review)
    let later = now.addingTimeInterval(3600)  // same day: short-term path
    let p = sch.preview(c, now: later)
    #expect(p[.hard]!.scheduledDays == 1)
    #expect(p[.good]!.scheduledDays == 2)
    #expect(p[.easy]!.scheduledDays == 3)
  }

  @Test func retrievabilityAtStabilityIsNinety() {
    let c = FSRSCard(stability: 10, difficulty: 5, due: now, lastReview: now, reps: 1, lapses: 0, state: .review)
    let at = cal.date(byAdding: .day, value: 10, to: now)!
    #expect(close(sch.retrievability(c, at: at), 0.9, 1e-9))
    #expect(sch.retrievability(.new(now: now), at: now) == 1)
  }

  @Test func clampingAndMaximumInterval() {
    let p = FSRSParameters(maximumInterval: 10)
    let s = FSRSScheduler(parameters: p, calendar: cal)
    let easy = s.next(.new(now: now), rating: .easy, now: now)
    #expect(days(easy, from: now) == 10)
    // Difficulty clamps to [1, 10].
    var c = FSRSCard(stability: 5, difficulty: 10, due: now, lastReview: now, reps: 2, lapses: 0, state: .review)
    let later = cal.date(byAdding: .day, value: 5, to: now)!
    let a = s.next(c, rating: .again, now: later)
    #expect(a.card.difficulty <= 10 && a.card.difficulty >= 1)
    c.difficulty = 1
    let e = s.next(c, rating: .easy, now: later)
    #expect(e.card.difficulty >= 1 && e.card.difficulty <= 10)
  }

  @Test func previewMatchesNext() {
    let (card, later) = goodCard()
    let p = sch.preview(card, now: later)
    for r in FSRSRating.allCases {
      #expect(p[r] == sch.next(card, rating: r, now: later))
    }
  }

  @Test func learningCardAgainStaysLearning() {
    let c = sch.next(.new(now: now), rating: .again, now: now).card
    let r = sch.next(c, rating: .again, now: now.addingTimeInterval(700))
    #expect(r.card.state == .learning)
    #expect(r.card.lapses == 0)
    let g = sch.next(c, rating: .good, now: now.addingTimeInterval(700))
    #expect(g.card.state == .review)
  }
}
