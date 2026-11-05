import PokerCore
import SwiftUI

/// Seven cards, five of which make the hand.
public struct BestFiveModel: Sendable, Hashable {
  public var cards: [Card]
  public var best: [Card]
  public var description: String

  public init(cards: [Card], best: [Card], description: String) {
    self.cards = cards
    self.best = best
    self.description = description
  }
}

public struct BestFiveHighlightView: View {
  @Environment(\.theme) private var theme
  private let model: BestFiveModel

  public init(model: BestFiveModel) { self.model = model }

  public var body: some View {
    VStack(spacing: 10) {
      Reveal { p in
        HStack(spacing: 6) {
          ForEach(Array(model.cards.enumerated()), id: \.offset) { _, card in
            let isBest = model.best.contains(card)
            let lift = isBest ? segment(p, 0.3, 0.9) : 0
            CardView(card: card)
              .shadow(color: theme.gold.opacity(0.95 * lift), radius: 9)
              .overlay(
                RoundedRectangle(cornerRadius: 6).strokeBorder(theme.gold, lineWidth: 2.5).opacity(lift)
              )
              .opacity(isBest ? 1 : 1 - 0.55 * segment(p, 0.3, 0.9))
              .offset(y: -12 * lift)
              .scaleEffect(1 + 0.06 * lift)
          }
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
      }
      Text(model.description)
        .font(theme.displayFont(size: 15))
        .foregroundStyle(theme.ink)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("explainer.bestFiveHighlight.description")
    }
    .frame(maxWidth: .infinity)
    .explainerSurface()
    .explainerContainer(
      "explainer.bestFiveHighlight",
      label: "\(model.description). Best five: \(model.best.map(cardName).joined(separator: ", "))")
  }
}
