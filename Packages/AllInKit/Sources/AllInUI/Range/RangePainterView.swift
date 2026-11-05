import PokerCore
import PokerEquity
import SwiftUI

/// Pure paint rules of the range painter. Grid order is `HandRange.grid` (Ace first).
public struct RangePainterLogic: Sendable, Hashable {
  public var weights: [[Float]]
  /// Value of the stroke in progress (set by the first cell touched).
  public private(set) var paintValue: Float?

  public init(weights: [[Float]]) {
    self.weights = Self.normalized(weights)
  }

  static func normalized(_ w: [[Float]]) -> [[Float]] {
    (0..<13).map { r in (0..<13).map { c in w.indices.contains(r) && w[r].indices.contains(c) ? w[r][c] : 0 } }
  }

  /// Click: 0 → 1, anything above 0 → 0. Returns the value written.
  @discardableResult
  public mutating func toggle(row: Int, column: Int) -> Float? {
    guard Self.contains(row, column) else { return nil }
    let value: Float = weights[row][column] > 0 ? 0 : 1
    weights[row][column] = value
    return value
  }

  /// First cell of a drag: toggles it and remembers its new value for the rest of the stroke.
  public mutating func beginStroke(row: Int, column: Int) {
    paintValue = toggle(row: row, column: column)
  }

  /// Further cells of the stroke take the first cell's value.
  public mutating func continueStroke(row: Int, column: Int) {
    guard let paintValue, Self.contains(row, column) else { return }
    weights[row][column] = paintValue
  }

  public mutating func endStroke() { paintValue = nil }

  public static func contains(_ row: Int, _ column: Int) -> Bool { (0..<13).contains(row) && (0..<13).contains(column) }

  /// Grid cell under `point` (grid origin top-left), or nil outside.
  public static func cell(at point: CGPoint, cellSize: CGFloat) -> (row: Int, column: Int)? {
    guard cellSize > 0, point.x >= 0, point.y >= 0 else { return nil }
    let row = Int(point.y / cellSize)
    let column = Int(point.x / cellSize)
    return contains(row, column) ? (row, column) : nil
  }
}

/// Paints a range on a 13×13 grid: a click toggles a cell, a drag paints with the first cell's new value.
public struct RangePainterView: View {
  @Environment(\.theme) private var theme
  @Binding private var weights: [[Float]]
  private let cellSize: CGFloat
  @State private var logic: RangePainterLogic?

  public init(weights: Binding<[[Float]]>, cellSize: CGFloat = 22) {
    self._weights = weights
    self.cellSize = cellSize
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(spacing: 0) {
        ForEach(0..<13, id: \.self) { row in
          HStack(spacing: 0) {
            ForEach(0..<13, id: \.self) { column in cell(row: row, column: column) }
          }
        }
      }
      .overlay(Rectangle().strokeBorder(theme.ink.opacity(0.7), lineWidth: 1))
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .onChanged { value in handle(value) }
          .onEnded { _ in logic = nil }
      )
      Text(summary)
        .font(theme.bodyFont(size: 12, weight: .medium))
        .foregroundStyle(theme.ink)
        .accessibilityIdentifier("rangePainter.summary")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("rangePainter")
  }

  private var summary: String {
    let clamped = RangePainterLogic.normalized(weights).map { row in row.map { min(max($0, 0), 1) } }
    return RangeGridModel(range: HandRange(grid: clamped)).summary
  }

  private func handle(_ value: DragGesture.Value) {
    guard let hit = RangePainterLogic.cell(at: value.location, cellSize: cellSize) else { return }
    if logic == nil {
      var fresh = RangePainterLogic(weights: weights)
      fresh.beginStroke(row: hit.row, column: hit.column)
      logic = fresh
    } else {
      logic?.continueStroke(row: hit.row, column: hit.column)
    }
    if let logic, logic.weights != weights { weights = logic.weights }
  }

  private func cell(row: Int, column: Int) -> some View {
    let w = weights.indices.contains(row) && weights[row].indices.contains(column) ? Double(weights[row][column]) : 0
    let filled = w > 0
    let label = RangeGridModel.label(row: row, column: column)
    return ZStack {
      Rectangle().fill(theme.parchment.opacity(0.6))
      Rectangle().fill(theme.gold.opacity(filled ? 0.25 + 0.75 * min(1, w) : 0))
      if cellSize >= 18 {
        Text(label)
          .font(theme.bodyFont(size: 9, weight: .semibold))
          .lineLimit(1)
          .foregroundStyle(theme.ink.opacity(filled ? 0.95 : 0.35))
      }
      Rectangle().strokeBorder(theme.ink.opacity(0.12), lineWidth: 0.5)
    }
    .frame(width: cellSize, height: cellSize)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(filled ? "\(Int((w * 100).rounded())) percent" : "empty")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      var l = RangePainterLogic(weights: weights)
      l.toggle(row: row, column: column)
      weights = l.weights
    }
    .accessibilityIdentifier("rangePainter.\(label)")
  }
}
