import Testing

@testable import PokerEquity

@Suite struct PokerEquitySmokeTests {
  @Test func moduleLinks() {
    #expect(PokerEquity.name == "PokerEquity")
  }
}
