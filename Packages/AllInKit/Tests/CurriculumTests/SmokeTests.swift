import Testing

@testable import Curriculum

@Suite struct CurriculumSmokeTests {
  @Test func moduleLinks() {
    #expect(Curriculum.name == "Curriculum")
  }
}
