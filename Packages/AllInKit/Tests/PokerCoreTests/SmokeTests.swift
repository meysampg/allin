import Testing

@testable import PokerCore

@Suite struct PokerCoreSmokeTests {
  @Test func moduleLinks() {
    #expect(PokerCore.name == "PokerCore")
  }
}
