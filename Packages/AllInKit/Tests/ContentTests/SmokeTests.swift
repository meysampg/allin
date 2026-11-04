import Testing

@testable import Curriculum

// Content validation lives here from M5 on (run with `Tools/test.sh content`).
@Suite struct ContentSmokeTests {
  @Test func curriculumLinks() {
    #expect(Curriculum.name == "Curriculum")
  }
}
