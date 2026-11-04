import Testing

@testable import PokerAnalysis

@Suite struct PokerAnalysisSmokeTests {
  @Test func moduleLinks() {
    #expect(PokerAnalysis.name == "PokerAnalysis")
  }
}
