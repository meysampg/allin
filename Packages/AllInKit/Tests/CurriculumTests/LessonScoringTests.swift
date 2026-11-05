import Testing

@testable import Curriculum

@Suite struct LessonScoringTests {
  private let spec = LessonStars()

  private func stars(_ puzzle: Bool?, _ good: Int, hints: Int = 0, spec: LessonStars? = nil) -> Int {
    LessonScoring.stars(spec ?? self.spec, puzzleGood: puzzle, applyGood: good, applyTotal: 3, hintsUsed: hints)
  }

  @Test func ruleMatrix() {
    #expect(stars(true, 3) == 3)
    #expect(stars(false, 3) == 2)
    #expect(stars(nil, 3) == 2)
    #expect(stars(true, 2) == 2)
    #expect(stars(true, 1) == 1)
    #expect(stars(false, 0) == 1)
  }

  @Test func hintFloor() {
    #expect(stars(true, 3, hints: 1) == 2)
    #expect(stars(true, 3, hints: 2) == 1)
    #expect(stars(true, 3, hints: 9) == 1)
    #expect(stars(true, 1, hints: 1) == 1)
    let costly = LessonStars(hintCost: 2)
    #expect(stars(true, 3, hints: 1, spec: costly) == 1)
    let free = LessonStars(hintCost: 0)
    #expect(stars(true, 3, hints: 5, spec: free) == 3)
  }

  @Test func drillStars() {
    #expect(LessonScoring.drillStars(good: 8, total: 10) == 3)
    #expect(LessonScoring.drillStars(good: 7, total: 10) == 2)
    #expect(LessonScoring.drillStars(good: 6, total: 10) == 2)
    #expect(LessonScoring.drillStars(good: 5, total: 10) == 1)
    #expect(LessonScoring.drillStars(good: 0, total: 0) == 1)
  }
}
