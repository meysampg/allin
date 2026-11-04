import Testing

@testable import TableKit

@Suite struct TableKitSmokeTests {
  @Test func moduleLinks() {
    #expect(TableKit.name == "TableKit")
  }
}
