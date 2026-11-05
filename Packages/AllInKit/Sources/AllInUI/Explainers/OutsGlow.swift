import PokerCore
import SwiftUI

/// Rule of 2 and 4: each out is worth about 2% on the next card and about 4% over two cards.
public struct OutsGlowModel: Sendable, Hashable {
  public var hole: [Card]
  public var board: [Card]
  public var outs: [Card]
  /// Cards the hero has not seen.
  public var unseen: Int
  /// Exact equity from the engine, shown next to the estimate when available.
  public var exactEquity: Double?

  public init(hole: [Card], board: [Card], outs: [Card], unseen: Int, exactEquity: Double? = nil) {
    self.hole = hole
    self.board = board
    self.outs = outs
    self.unseen = unseen
    self.exactEquity = exactEquity
  }

  /// outs / unseen
  public var nextCard: Double {
    guard unseen > 0 else { return 0 }
    return min(1, Double(outs.count) / Double(unseen))
  }

  /// On the flop only: 1 − (1 − o/u)(1 − o/(u−1)).
  public var byRiver: Double? {
    guard board.count == 3, unseen > 1 else { return nil }
    let o = Double(outs.count)
    let u = Double(unseen)
    return 1 - (1 - o / u) * (1 - o / (u - 1))
  }

  public var caption: String {
    let count = outs.count
    let each = "\(count) \(count == 1 ? "out" : "outs") × ~2% per card"
    var text: String
    if let river = byRiver {
      text = "\(each) ≈ \(percentText(nextCard)) next card, ~\(percentText(river)) by the river."
    } else {
      text = "\(count) \(count == 1 ? "out" : "outs") of \(unseen) unseen cards ≈ \(percentText(nextCard)) next card."
    }
    if let exactEquity { text += " Exact equity: \(percentText(exactEquity))." }
    return text
  }
}

public struct OutsGlowView: View {
  @Environment(\.theme) private var theme
  private let model: OutsGlowModel
  private let cell = CGSize(width: 25, height: 31)

  public init(model: OutsGlowModel) { self.model = model }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Reveal { p in deck(progress: p) }
        .frame(width: cell.width * 13 + 12 * 2, height: cell.height * 4 + 3 * 3)
        .accessibilityHidden(true)
      HStack(spacing: 6) {
        Tag("Next card \(percentText(model.nextCard))", style: .gold)
          .accessibilityIdentifier("explainer.outsGlow.nextCard")
        if let river = model.byRiver {
          Tag("By the river \(percentText(river))", style: .good)
            .accessibilityIdentifier("explainer.outsGlow.byRiver")
        }
        Tag("\(model.outs.count) outs", style: .plain).accessibilityIdentifier("explainer.outsGlow.outs")
      }
      Text(model.caption)
        .font(theme.bodyFont(size: 13, weight: .medium))
        .foregroundStyle(theme.ink)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("explainer.outsGlow.caption")
    }
    .explainerSurface()
    .explainerContainer("explainer.outsGlow", label: model.caption)
  }

  private func deck(progress p: Double) -> some View {
    let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]
    let known = Set(model.hole + model.board)
    let outs = Set(model.outs)
    let order = Dictionary(uniqueKeysWithValues: model.outs.enumerated().map { ($1, $0) })
    return Canvas { context, _ in
      for (row, suit) in suits.enumerated() {
        for col in 0..<13 {
          let rank = Rank(rawValue: UInt8(12 - col))!
          let card = Card(rank: rank, suit: suit)
          let rect = CGRect(
            x: Double(col) * (cell.width + 2), y: Double(row) * (cell.height + 3), width: cell.width,
            height: cell.height)
          let isOut = outs.contains(card)
          let lit = isOut ? segment(p, 0.2 + 0.6 * Double(order[card] ?? 0) / Double(max(1, outs.count)), 1) : 0
          let glow = min(1, lit * 1.4)
          var shape = Path(roundedRect: rect, cornerRadius: 4)
          if isOut && glow > 0 {
            let lifted = rect.offsetBy(dx: 0, dy: -3 * glow)
            shape = Path(roundedRect: lifted, cornerRadius: 4)
            context.fill(
              Path(roundedRect: lifted.insetBy(dx: -3, dy: -3), cornerRadius: 6),
              with: .color(theme.gold.opacity(0.45 * glow)))
          }
          let base = theme.color(.cardFace)
          context.fill(shape, with: .color(isOut && glow > 0 ? base : base.opacity(known.contains(card) ? 0.18 : 0.5)))
          context.stroke(
            shape, with: .color(isOut && glow > 0 ? theme.gold : theme.ink.opacity(0.3)),
            lineWidth: isOut && glow > 0 ? 2 : 1)
          let faded = known.contains(card) ? 0.25 : (isOut ? 1 : 0.45)
          let tint = theme.suitColor(suit, fourColor: false).opacity(isOut && glow > 0 ? 1 : faded)
          let origin = shape.boundingRect
          context.draw(
            Text(rankText(rank)).font(.system(size: 10, weight: .bold, design: .serif)).foregroundColor(tint),
            at: CGPoint(x: origin.midX, y: origin.minY + 10), anchor: .center)
          context.draw(
            Text(suitGlyph(suit)).font(.system(size: 12, design: .serif)).foregroundColor(tint),
            at: CGPoint(x: origin.midX, y: origin.minY + 22), anchor: .center)
          if known.contains(card) {
            context.stroke(
              Path {
                $0.move(to: CGPoint(x: rect.minX + 3, y: rect.maxY - 3));
                $0.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3))
              },
              with: .color(theme.mute.opacity(0.6)), lineWidth: 1)
          }
        }
      }
    }
  }
}
