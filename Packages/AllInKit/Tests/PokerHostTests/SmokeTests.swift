import Testing

@testable import PokerHost

@Suite struct PokerHostSmokeTests {
  @Test func moduleLinks() {
    #expect(PokerHost.name == "PokerHost")
  }
}
