import Testing

@testable import PokerAI
@testable import PokerHost

// Release-only bot simulations (run with `Tools/test.sh sim`).
@Suite struct SimSmokeTests {
  @Test func hostAndAILink() {
    #expect(PokerHost.name == "PokerHost")
    #expect(PokerAI.name == "PokerAI")
  }
}
