import PokerCore
import PokerEquity

/// The numbers behind a 13×13 range grid.
public struct RangeGridModel: Sendable, Hashable {
  /// `HandRange.grid`: row and column 0 are the Ace, suited above the diagonal.
  public let cells: [[Float]]
  /// `range.totalWeight`.
  public let weightedCombos: Double
  /// Combos not blocked by the dead cards.
  public let liveCombos: Int

  public init(range: HandRange, dead: CardSet = CardSet()) {
    cells = range.grid
    weightedCombos = range.totalWeight
    liveCombos = Combo.all.reduce(0) { $0 + ($1.mask.isDisjoint(with: dead) ? 1 : 0) }
  }

  public var percentOfLive: Double {
    liveCombos > 0 ? weightedCombos / Double(liveCombos) : 0
  }

  public static func label(row: Int, column: Int) -> String {
    HandClass(gridRow: row, gridColumn: column).description
  }

  /// "≈ 312 combos · 24% of hands"
  public var summary: String {
    let combos = Int(weightedCombos.rounded())
    let percent = Int((percentOfLive * 100).rounded())
    return "≈ \(combos) combos · \(percent)% of hands"
  }
}
