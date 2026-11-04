import Testing

@testable import ThemeKit

@Suite struct ThemeKitSmokeTests {
  @Test func moduleLinks() {
    #expect(ThemeKit.name == "ThemeKit")
  }
}
