import Testing

@testable import PokerCore

// Release-only exhaustive and property tests (run with `Tools/test.sh heavy`).
@Suite struct HeavySmokeTests {
  @Test func pokerCoreLinks() {
    #expect(PokerCore.name == "PokerCore")
  }
}
