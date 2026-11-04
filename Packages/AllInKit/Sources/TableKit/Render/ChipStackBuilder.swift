import Foundation
import ThemeKit

public struct ChipCount: Sendable, Hashable {
  public let denomination: ChipDenomination
  public let count: Int

  public init(denomination: ChipDenomination, count: Int) {
    self.denomination = denomination
    self.count = count
  }
}

public enum ChipStackBuilder {
  /// Greedy, largest first, exact sum. A remainder the `available` set cannot make is paid in `.one` chips.
  public static func breakdown(
    _ amount: Int, available: [ChipDenomination] = ChipDenomination.allCases
  ) -> [ChipCount] {
    guard amount > 0 else { return [] }
    var remaining = amount
    var result: [ChipCount] = []
    for denomination in Set(available).sorted(by: >) where remaining >= denomination.rawValue {
      let count = remaining / denomination.rawValue
      result.append(ChipCount(denomination: denomination, count: count))
      remaining -= count * denomination.rawValue
    }
    if remaining > 0 {
      if let index = result.firstIndex(where: { $0.denomination == .one }) {
        result[index] = ChipCount(denomination: .one, count: result[index].count + remaining)
      } else {
        result.append(ChipCount(denomination: .one, count: remaining))
      }
    }
    return result
  }

  /// Visual stacks, bottom to top, largest chips first. The total is capped at `maxPerColumn * maxColumns`
  /// by keeping the largest chips, so very large amounts are drawn approximately.
  public static func columns(for amount: Int, maxPerColumn: Int = 10, maxColumns: Int = 4) -> [[ChipDenomination]] {
    let perColumn = max(maxPerColumn, 1)
    let columnLimit = max(maxColumns, 1)
    var flat: [ChipDenomination] = []
    for entry in breakdown(amount) {
      flat += Array(repeating: entry.denomination, count: entry.count)
      if flat.count >= perColumn * columnLimit { break }
    }
    flat = Array(flat.prefix(perColumn * columnLimit))
    // One column per run of equal denominations, split at the height cap.
    var columns: [[ChipDenomination]] = []
    var index = 0
    while index < flat.count {
      var end = index
      while end < flat.count, flat[end] == flat[index], end - index < perColumn { end += 1 }
      columns.append(Array(flat[index..<end]))
      index = end
    }
    // Too many columns: fold the smallest into the last allowed column.
    while columns.count > columnLimit {
      let last = columns.removeLast()
      columns[columns.count - 1] = Array((columns[columns.count - 1] + last).prefix(perColumn))
    }
    return columns
  }
}
