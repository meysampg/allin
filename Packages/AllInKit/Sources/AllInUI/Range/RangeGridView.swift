import PokerCore
import PokerEquity
import SwiftUI

/// A 13×13 hand grid: gold fill by weight, class labels, optional highlighted class.
public struct RangeGridView: View {
  @Environment(\.theme) private var theme
  private let model: RangeGridModel
  private let highlight: HandClass?
  private let cellSize: CGFloat
  private let showsLabels: Bool

  public init(
    range: HandRange, dead: CardSet = CardSet(), highlight: HandClass? = nil, cellSize: CGFloat = 18,
    showsLabels: Bool = true
  ) {
    model = RangeGridModel(range: range, dead: dead)
    self.highlight = highlight
    self.cellSize = cellSize
    self.showsLabels = showsLabels
  }

  public var body: some View {
    VStack(spacing: 0) {
      ForEach(0..<13, id: \.self) { row in
        HStack(spacing: 0) {
          ForEach(0..<13, id: \.self) { column in
            cell(row: row, column: column)
          }
        }
      }
    }
    .overlay(Rectangle().strokeBorder(theme.ink.opacity(0.7), lineWidth: 1))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(model.summary)
    .accessibilityIdentifier("rangeGrid")
  }

  private func cell(row: Int, column: Int) -> some View {
    let weight = Double(model.cells[row][column])
    let isHighlighted = highlight.map { $0.gridRow == row && $0.gridColumn == column } ?? false
    let filled = weight > 0
    return ZStack {
      Rectangle().fill(theme.parchment.opacity(0.6))
      Rectangle().fill(theme.gold.opacity(filled ? 0.12 + 0.88 * min(1, weight) : 0))
      if showsLabels {
        Text(RangeGridModel.label(row: row, column: column))
          .font(theme.bodyFont(size: 9, weight: .semibold))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .foregroundStyle(theme.ink.opacity(filled ? 0.95 : 0.35))
      }
      Rectangle().strokeBorder(theme.ink.opacity(0.12), lineWidth: 0.5)
      if isHighlighted {
        Rectangle().strokeBorder(theme.gold, lineWidth: 2)
      }
    }
    .frame(width: cellSize, height: cellSize)
  }
}
