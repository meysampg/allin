import PokerCore
import PokerEquity
import SwiftUI

public enum WhoCallsMode: String, Sendable { case callers, bettors }

/// A 13×13 range grid colored by what the villain does against the hero's hand.
public struct WhoCallsMeModel: Sendable, Hashable {
  public enum Cell: String, Sendable { case none, worseCalls, betterCalls, folds }

  public var mode: WhoCallsMode
  public var villainName: String
  public var heroCards: [Card]
  public var board: [Card]
  /// 13×13 in `HandRange.grid` order (Ace first, suited above the diagonal).
  public var cells: [[Cell]]
  /// Shares of the villain's range, 0...1.
  public var worseCalls: Double
  public var betterCalls: Double
  public var folds: Double
  public var betLabel: String?

  public init(
    mode: WhoCallsMode, villainName: String, heroCards: [Card], board: [Card], cells: [[Cell]], worseCalls: Double,
    betterCalls: Double, folds: Double, betLabel: String? = nil
  ) {
    self.mode = mode
    self.villainName = villainName
    self.heroCards = heroCards
    self.board = board
    self.cells = cells
    self.worseCalls = worseCalls
    self.betterCalls = betterCalls
    self.folds = folds
    self.betLabel = betLabel
  }

  /// worseCalls + betterCalls + folds (about 1 when the shares cover the whole range).
  public var total: Double { worseCalls + betterCalls + folds }
  public var callShare: Double { worseCalls + betterCalls }

  public var summary: String {
    let who = mode == .callers ? "calls" : "bets"
    return
      "\(villainName) \(who) with worse \(percentText(worseCalls)) and better \(percentText(betterCalls)) "
      + "of the time; folds \(percentText(folds))."
  }

  var legend: [(cell: Cell, title: String, share: Double)] {
    switch mode {
    case .callers:
      [
        (.worseCalls, "Worse hands that call", worseCalls), (.betterCalls, "Better hands that call", betterCalls),
        (.folds, "Hands that fold", folds),
      ]
    case .bettors:
      [
        (.worseCalls, "Worse hands that bet", worseCalls), (.betterCalls, "Better hands that bet", betterCalls),
        (.folds, "Hands that check or fold", folds),
      ]
    }
  }
}

public struct WhoCallsMeView: View {
  @Environment(\.theme) private var theme
  private let model: WhoCallsMeModel
  private let cellSize: CGFloat = 21

  public init(model: WhoCallsMeModel) { self.model = model }

  public var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Reveal { p in grid(progress: p) }
        .frame(width: cellSize * 13, height: cellSize * 13)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 8) {
        Text(model.mode == .callers ? "Who calls me?" : "Who bets into me?")
          .font(theme.displayFont(size: 15)).foregroundStyle(theme.ink)
        Text(model.villainName).font(theme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(theme.mute)
        HStack(spacing: 3) {
          ForEach(Array(model.heroCards.enumerated()), id: \.offset) { _, c in CardView(card: c, size: .width(26)) }
          Rectangle().fill(theme.ink.opacity(0.3)).frame(width: 1, height: 30).padding(.horizontal, 3)
          ForEach(Array(model.board.enumerated()), id: \.offset) { _, c in CardView(card: c, size: .width(26)) }
        }
        if let betLabel = model.betLabel {
          Tag(betLabel, style: .dark).accessibilityIdentifier("explainer.whoCallsMe.bet")
        }
        ForEach(Array(model.legend.enumerated()), id: \.offset) { index, item in
          HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color(item.cell)).frame(width: 14, height: 14)
              .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(theme.ink.opacity(0.5), lineWidth: 1))
            Text(item.title).font(theme.bodyFont(size: 12)).foregroundStyle(theme.ink)
            Spacer(minLength: 4)
            Text(percentText(item.share)).font(theme.bodyFont(size: 13, weight: .bold)).foregroundStyle(theme.ink)
              .accessibilityIdentifier("explainer.whoCallsMe.\(["worse", "better", "folds"][index])")
          }
        }
      }
      .frame(width: 230)
    }
    .explainerSurface()
    .explainerContainer("explainer.whoCallsMe", label: model.summary)
  }

  private func color(_ cell: WhoCallsMeModel.Cell) -> Color {
    switch cell {
    case .none: theme.parchment.opacity(0.35)
    case .worseCalls: theme.good
    case .betterCalls: theme.bad
    case .folds: theme.mute.opacity(0.45)
    }
  }

  private func grid(progress p: Double) -> some View {
    Canvas { context, _ in
      for row in 0..<13 {
        for col in 0..<13 {
          let rect = CGRect(x: CGFloat(col) * cellSize, y: CGFloat(row) * cellSize, width: cellSize, height: cellSize)
          let cell =
            model.cells.indices.contains(row) && model.cells[row].indices.contains(col) ? model.cells[row][col] : .none
          let reveal = segment(p, Double(row + col) / 24 * 0.7, Double(row + col) / 24 * 0.7 + 0.3)
          context.fill(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(theme.parchment.opacity(0.35)))
          context.fill(
            Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 3),
            with: .color(color(cell).opacity(reveal)))
          let label = RangeGridModel.label(row: row, column: col)
          let bright = cell == .worseCalls || cell == .betterCalls
          context.draw(
            Text(label).font(.system(size: 9, weight: .semibold, design: .rounded))
              .foregroundColor(bright ? Color.white.opacity(reveal) : theme.ink.opacity(cell == .none ? 0.3 : 0.55)),
            at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
      }
      context.stroke(
        Path(CGRect(x: 0, y: 0, width: cellSize * 13, height: cellSize * 13)), with: .color(theme.ink.opacity(0.7)),
        lineWidth: 1)
    }
  }
}
