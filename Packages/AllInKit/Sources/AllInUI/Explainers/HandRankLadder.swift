import PokerCore
import SwiftUI

/// The nine hand categories, best on top; `highlights` tags the categories players hold.
public struct HandLadderModel: Sendable, Hashable {
  public var highlights: [HandCategory: String]

  public init(highlights: [HandCategory: String] = [:]) { self.highlights = highlights }

  /// Best to worst.
  public static let order: [HandCategory] = HandCategory.allCases.reversed()

  static func example(_ category: HandCategory) -> String {
    switch category {
    case .straightFlush: "9♥ 8♥ 7♥ 6♥ 5♥"
    case .fourOfAKind: "K♠ K♥ K♦ K♣ 4♠"
    case .fullHouse: "Q♠ Q♥ Q♦ 7♣ 7♠"
    case .flush: "A♦ J♦ 8♦ 5♦ 2♦"
    case .straight: "T♠ 9♥ 8♦ 7♣ 6♠"
    case .threeOfAKind: "8♠ 8♥ 8♦ K♣ 3♠"
    case .twoPair: "J♠ J♥ 4♦ 4♣ A♠"
    case .pair: "A♠ A♥ 9♦ 6♣ 3♠"
    case .highCard: "A♠ J♥ 8♦ 5♣ 2♠"
    }
  }
}

public struct HandRankLadderView: View {
  @Environment(\.theme) private var theme
  private let model: HandLadderModel

  public init(model: HandLadderModel) { self.model = model }

  public var body: some View {
    Reveal { p in
      VStack(spacing: 3) {
        ForEach(Array(HandLadderModel.order.enumerated()), id: \.offset) { index, category in
          row(rank: index + 1, category: category, shown: segment(p, 0.08 * Double(index), 0.08 * Double(index) + 0.3))
        }
      }
    }
    .explainerSurface()
    .explainerContainer("explainer.handRankLadder", label: "Hand ranks, best to worst")
  }

  private func row(rank: Int, category: HandCategory, shown: Double) -> some View {
    let tag = model.highlights[category]
    let top = rank == 1
    return HStack(spacing: 10) {
      Text("\(rank)")
        .font(theme.displayFont(size: 12))
        .foregroundStyle(theme.parchment)
        .frame(width: 22, height: 22)
        .background(Circle().fill(top ? theme.gold.mix(with: theme.ink, by: 0.2) : theme.ink.opacity(0.75)))
      Text(category.title)
        .font(theme.displayFont(size: 14))
        .foregroundStyle(theme.ink)
        .frame(width: 130, alignment: .leading)
      exampleText(HandLadderModel.example(category))
        .frame(maxWidth: .infinity, alignment: .leading)
      if let tag {
        Tag(tag, style: .gold)
      }
    }
    .padding(.vertical, 3)
    .padding(.horizontal, 8)
    .frame(minHeight: 30)
    .background(
      RoundedRectangle(cornerRadius: 6).fill(tag != nil ? theme.gold.opacity(0.28) : theme.parchment.opacity(0.5))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6).strokeBorder(
        tag != nil ? theme.gold : theme.ink.opacity(0.15), lineWidth: tag != nil ? 2 : 1)
    )
    .opacity(shown)
    .offset(x: -16 * (1 - shown))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(rank). \(category.title)" + (tag.map { ", \($0)" } ?? ""))
    .accessibilityIdentifier(
      "explainer.handRankLadder.\(category.name.lowercased().replacingOccurrences(of: " ", with: "-"))")
  }

  private func exampleText(_ text: String) -> some View {
    let cards = text.split(separator: " ")
    return HStack(spacing: 6) {
      ForEach(Array(cards.enumerated()), id: \.offset) { _, token in
        let suit = token.last!
        let red = suit == "♥" || suit == "♦"
        Text(String(token))
          .font(.system(size: 12, weight: .bold, design: .serif))
          .foregroundColor(red ? theme.color(.suitRed) : theme.color(.suitBlack))
      }
    }
  }
}
