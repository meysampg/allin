import Testing
import ThemeKit

@testable import TableKit

@Suite struct ChipStackBuilderTests {
  @Test func breakdownOf1234() {
    let expected = [
      ChipCount(denomination: .thousand, count: 1), ChipCount(denomination: .hundred, count: 2),
      ChipCount(denomination: .twentyFive, count: 1), ChipCount(denomination: .five, count: 1),
      ChipCount(denomination: .one, count: 4),
    ]
    #expect(ChipStackBuilder.breakdown(1234) == expected)
  }

  @Test func breakdownSumsExactly() {
    for amount in stride(from: 1, through: 5000, by: 7) {
      let total = ChipStackBuilder.breakdown(amount).reduce(0) { $0 + $1.denomination.rawValue * $1.count }
      #expect(total == amount)
    }
  }

  @Test func zeroIsEmpty() {
    #expect(ChipStackBuilder.breakdown(0).isEmpty)
    #expect(ChipStackBuilder.columns(for: 0).isEmpty)
  }

  @Test func restrictedDenominationsStillSum() {
    for amount in [1, 3, 24, 99, 130, 777, 12_345] {
      let parts = ChipStackBuilder.breakdown(amount, available: [.hundred, .twentyFive])
      #expect(parts.reduce(0) { $0 + $1.denomination.rawValue * $1.count } == amount)
    }
    #expect(ChipStackBuilder.breakdown(130, available: [.hundred]).last == ChipCount(denomination: .one, count: 30))
  }

  @Test func columnsRespectCaps() {
    for amount in [7, 135, 1234, 26_480, 1_000_000] {
      let columns = ChipStackBuilder.columns(for: amount)
      #expect(!columns.isEmpty)
      #expect(columns.count <= 4)
      #expect(columns.allSatisfy { !$0.isEmpty && $0.count <= 10 })
    }
    let huge = ChipStackBuilder.columns(for: 1_000_000)
    #expect(huge.reduce(0) { $0 + $1.count } == 40)
    #expect(huge.count == 4)
    #expect(ChipStackBuilder.columns(for: 1_000_000, maxPerColumn: 3, maxColumns: 2).flatMap { $0 }.count == 6)
  }
}
