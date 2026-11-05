import PokerCore
import SwiftUI

/// Pure selection rules of the card picker.
public enum CardPickerLogic {
  /// Toggles `card`. Dead cards never change the selection. Adding past `limit` drops the oldest selections.
  public static func toggled(_ selection: [Card], card: Card, limit: Int?, dead: CardSet = CardSet()) -> [Card] {
    guard !dead.contains(card) else { return selection }
    if let index = selection.firstIndex(of: card) {
      var next = selection
      next.remove(at: index)
      return next
    }
    var next = selection + [card]
    if let limit { next = Array(next.suffix(max(0, limit))) }
    return next
  }

  /// Selection without dead cards and duplicates, trimmed to the newest `limit`.
  public static func sanitized(_ selection: [Card], limit: Int?, dead: CardSet) -> [Card] {
    var seen = CardSet()
    let kept = selection.filter { !dead.contains($0) && seen.insert($0) }
    guard let limit else { return kept }
    return Array(kept.suffix(max(0, limit)))
  }
}

/// A 4×13 grid of all 52 cards; tapping toggles a card.
public struct CardPickerView: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding private var selection: [Card]
  private let limit: Int?
  private let dead: CardSet
  private let fourColor: Bool
  private let tile = CGSize(width: 32, height: 44)

  public init(selection: Binding<[Card]>, limit: Int?, dead: CardSet = CardSet(), fourColor: Bool = false) {
    self._selection = selection
    self.limit = limit
    self.dead = dead
    self.fourColor = fourColor
  }

  private static let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]

  public var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(Self.suits, id: \.self) { suit in
        HStack(spacing: 3) {
          ForEach((0..<13).reversed(), id: \.self) { r in
            tileView(Card(rank: Rank(rawValue: UInt8(r))!, suit: suit))
          }
        }
      }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.parchment.opacity(0.55)))
    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.ink.opacity(0.25), lineWidth: 1))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("cardPicker")
  }

  private func tileView(_ card: Card) -> some View {
    let order = selection.firstIndex(of: card)
    let isDead = dead.contains(card)
    let selected = order != nil
    let color = theme.suitColor(card.suit, fourColor: fourColor)
    return Button {
      let next = CardPickerLogic.toggled(selection, card: card, limit: limit, dead: dead)
      if reduceMotion {
        selection = next
      } else {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { selection = next }
      }
    } label: {
      ZStack(alignment: .topTrailing) {
        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.color(.cardFace))
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .strokeBorder(selected ? theme.gold : theme.ink.opacity(0.45), lineWidth: selected ? 2.5 : 1)
        VStack(spacing: 0) {
          Text(rankText(card.rank)).font(.system(size: 14, weight: .bold, design: .serif))
          Text(suitGlyph(card.suit)).font(.system(size: 15, design: .serif))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        if let order, (limit ?? 2) > 1 {
          Text("\(order + 1)")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(theme.parchment)
            .frame(width: 13, height: 13)
            .background(Circle().fill(theme.ink))
            .offset(x: 3, y: -3)
        }
        if isDead {
          Path { p in
            p.move(to: CGPoint(x: 4, y: tile.height - 4))
            p.addLine(to: CGPoint(x: tile.width - 4, y: 4))
          }
          .stroke(theme.mute, lineWidth: 1.5)
        }
      }
      .frame(width: tile.width, height: tile.height)
      .shadow(color: theme.gold.opacity(selected ? 0.9 : 0), radius: 5)
      .opacity(isDead ? 0.3 : 1)
      .offset(y: selected ? -5 : 0)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDead)
    .accessibilityLabel(cardName(card))
    .accessibilityValue(isDead ? "dead" : (selected ? "selected" : "not selected"))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("cardPicker.\(card.description)")
  }
}
