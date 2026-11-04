import Testing

@testable import PokerAI

@Suite struct PokerAISmokeTests {
  @Test func moduleLinks() {
    #expect(PokerAI.name == "PokerAI")
  }
}
