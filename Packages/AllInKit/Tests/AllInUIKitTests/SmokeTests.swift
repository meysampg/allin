import Testing

@testable import AllInUI

@Suite struct AllInUISmokeTests {
  @Test func moduleLinks() {
    #expect(AllInUI.name == "AllInUI")
  }
}
