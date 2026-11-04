import Testing

@testable import Curriculum

@Suite struct CoachEngineTests {
  @Test func thresholds() {
    #expect(CoachEngine.level(meter: 0.39) == .full)
    #expect(CoachEngine.level(meter: 0.40) == .questions)
    #expect(CoachEngine.level(meter: 0.75) == .questions)
    #expect(CoachEngine.level(meter: 0.76) == .hidden)
  }

  @Test func meanOfMeters() {
    #expect(CoachEngine.level(meters: []) == .full)
    #expect(CoachEngine.level(meters: [0.2, 0.7]) == .questions)
    #expect(CoachEngine.level(meters: [0.9, 0.8]) == .hidden)
    #expect(CoachEngine.level(meters: [0, 0.5]) == .full)
  }

  @Test func rangeButtonOnlyAtFull() {
    #expect(CoachEngine.showsRangeButton(.full))
    #expect(!CoachEngine.showsRangeButton(.questions))
    #expect(!CoachEngine.showsRangeButton(.hidden))
  }

  @Test func beginnerQuestions() {
    let q = CoachEngine.thinkFirst(tier: .beginner)
    #expect(
      q.map(\.text) == [
        "What hands does {villain} play like this?",
        "How does your hand do against those?",
        "What does each of your moves achieve?",
      ])
    #expect(q.map(\.topic) == [.ranges, .equity, .actionPurpose])
    #expect(CoachEngine.tier(forVenueIndex: 0) == .beginner)
    #expect(CoachEngine.tier(forVenueIndex: 1) == .standard)
  }
}
