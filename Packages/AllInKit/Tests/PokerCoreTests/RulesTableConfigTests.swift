import Testing

@testable import PokerCore

@Suite struct RulesTableConfigTests {
  @Test func validConfig() throws {
    let c = try TableConfig(seatCount: 6, smallBlind: 50, bigBlind: 100, ante: 100, anteKind: .bigBlind, chipUnit: 25)
    #expect(c.seatCount == 6 && c.bigBlind == 100 && c.anteKind == .bigBlind)
  }

  @Test func rejectsSeatCountOutsideTwoToNine() {
    #expect(throws: TableConfigError.seatCountOutOfRange(1)) {
      try TableConfig(seatCount: 1, smallBlind: 1, bigBlind: 2)
    }
    #expect(throws: TableConfigError.seatCountOutOfRange(10)) {
      try TableConfig(seatCount: 10, smallBlind: 1, bigBlind: 2)
    }
  }

  @Test func rejectsBadBlindsAnteAndUnit() {
    #expect(throws: TableConfigError.nonPositiveSmallBlind(0)) {
      try TableConfig(seatCount: 6, smallBlind: 0, bigBlind: 2)
    }
    #expect(throws: TableConfigError.bigBlindBelowSmallBlind(small: 5, big: 2)) {
      try TableConfig(seatCount: 6, smallBlind: 5, bigBlind: 2)
    }
    #expect(throws: TableConfigError.negativeAnte(-1)) {
      try TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2, ante: -1)
    }
    #expect(throws: TableConfigError.nonPositiveChipUnit(0)) {
      try TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2, chipUnit: 0)
    }
    #expect(throws: TableConfigError.notMultipleOfChipUnit(name: "smallBlind", value: 30, chipUnit: 25)) {
      try TableConfig(seatCount: 6, smallBlind: 30, bigBlind: 50, chipUnit: 25)
    }
  }
}
