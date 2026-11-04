import Testing

@testable import AllInStore

@Suite struct AllInStoreSmokeTests {
  @Test func moduleLinks() {
    #expect(AllInStore.name == "AllInStore")
  }
}
