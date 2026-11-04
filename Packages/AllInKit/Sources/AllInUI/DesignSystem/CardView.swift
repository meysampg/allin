import PokerCore
import SwiftUI

public enum CardViewSize: Sendable {
  case regular
  case small
  case width(CGFloat)

  var dimensions: CGSize {
    switch self {
    case .regular: return CGSize(width: 44, height: 62)
    case .small: return CGSize(width: 30, height: 42)
    case .width(let w): return CGSize(width: w, height: (w * 62 / 44).rounded())
    }
  }
}

public struct CardView: View {
  @Environment(\.theme) private var theme
  private let card: Card?
  private let faceDown: Bool
  private let size: CardViewSize
  private let fourColor: Bool

  public init(card: Card?, faceDown: Bool = false, size: CardViewSize = .regular, fourColor: Bool = false) {
    self.card = card
    self.faceDown = faceDown
    self.size = size
    self.fourColor = fourColor
  }

  public var body: some View {
    let dims = size.dimensions
    Canvas { context, canvasSize in
      draw(in: &context, size: canvasSize)
    }
    .frame(width: dims.width, height: dims.height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private func draw(in context: inout GraphicsContext, size: CGSize) {
    let radius = size.width * 0.12
    let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
    let shape = Path(roundedRect: rect, cornerRadius: radius)
    if faceDown {
      context.fill(shape, with: .color(theme.ink))
      drawLattice(in: &context, rect: rect.insetBy(dx: size.width * 0.1, dy: size.width * 0.1), clip: shape)
      context.stroke(shape, with: .color(theme.gold), lineWidth: 1.5)
    } else if let card {
      context.fill(shape, with: .color(theme.color(.cardFace)))
      context.stroke(shape, with: .color(theme.ink.opacity(0.7)), lineWidth: 1)
      let color = theme.suitColor(card.suit, fourColor: fourColor)
      let rank = Text(card.rank == .ten ? "10" : String(card.rank.symbol))
        .font(.system(size: size.width * 0.42, weight: .bold, design: .serif))
        .foregroundColor(color)
      let suit = Text(Self.glyph(card.suit))
        .font(.system(size: size.width * 0.5, weight: .regular, design: .serif))
        .foregroundColor(color)
      context.draw(rank, at: CGPoint(x: size.width * 0.5, y: size.height * 0.3), anchor: .center)
      context.draw(suit, at: CGPoint(x: size.width * 0.5, y: size.height * 0.68), anchor: .center)
    } else {
      context.stroke(
        shape, with: .color(theme.mute),
        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }
  }

  private func drawLattice(in context: inout GraphicsContext, rect: CGRect, clip: Path) {
    var lattice = Path()
    let step = max(rect.width / 4, 4)
    var offset = -rect.height
    while offset < rect.width {
      lattice.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
      lattice.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
      lattice.move(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
      lattice.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
      offset += step
    }
    var inner = context
    inner.clip(to: Path(roundedRect: rect, cornerRadius: 3))
    inner.stroke(lattice, with: .color(theme.gold.opacity(0.7)), lineWidth: 1)
    context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(theme.gold), lineWidth: 1)
  }

  private static func glyph(_ suit: Suit) -> String {
    switch suit {
    case .clubs: return "\u{2663}"
    case .diamonds: return "\u{2666}"
    case .hearts: return "\u{2665}"
    case .spades: return "\u{2660}"
    }
  }

  private var accessibilityText: String {
    guard !faceDown, let card else { return faceDown ? "face-down card" : "empty card slot" }
    let ranks = [
      "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace",
    ]
    let suits = ["clubs", "diamonds", "hearts", "spades"]
    return "\(ranks[Int(card.rank.rawValue)]) of \(suits[Int(card.suit.rawValue)])"
  }
}
