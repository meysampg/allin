import PokerCore
import SwiftUI

/// The four betting rounds with the board and the actions that happened on each.
public struct TimelineModel: Sendable, Hashable {
  public struct Street: Sendable, Hashable {
    public var name: String
    public var board: [Card]
    public var actions: [String]

    public init(name: String, board: [Card], actions: [String]) {
      self.name = name
      self.board = board
      self.actions = actions
    }
  }

  public var streets: [Street]
  /// Index of the street being played.
  public var current: Int

  public init(streets: [Street], current: Int) {
    self.streets = streets
    self.current = current
  }
}

public struct BettingRoundsTimelineView: View {
  @Environment(\.theme) private var theme
  private let model: TimelineModel

  public init(model: TimelineModel) { self.model = model }

  public var body: some View {
    Reveal { p in
      HStack(alignment: .top, spacing: 0) {
        ForEach(Array(model.streets.enumerated()), id: \.offset) { index, street in
          column(index: index, street: street, progress: p)
        }
      }
    }
    .explainerSurface()
    .explainerContainer("explainer.bettingRoundsTimeline", label: label)
  }

  private var label: String {
    guard model.streets.indices.contains(model.current) else { return "Betting rounds" }
    return "Betting rounds. Now: \(model.streets[model.current].name)."
  }

  private func column(index: Int, street: TimelineModel.Street, progress p: Double) -> some View {
    let count = max(1, model.streets.count)
    let reach = Double(model.current) * segment(p, 0, 0.7)
    let isCurrent = index == model.current
    let passed = Double(index) <= reach + 0.001
    let cardsOpacity = segment(p, 0.25 + 0.5 * Double(index) / Double(count), 0.7 + 0.3 * Double(index) / Double(count))
    return VStack(spacing: 8) {
      HStack(spacing: 0) {
        Rectangle()
          .fill(index > 0 && Double(index) - 0.5 <= reach ? theme.gold : theme.ink.opacity(0.2))
          .frame(height: 3).opacity(index == 0 ? 0 : 1)
        ZStack {
          Circle().fill(passed ? theme.gold : theme.parchment)
          Circle().strokeBorder(theme.ink.opacity(0.8), lineWidth: 2)
          Text("\(index + 1)").font(theme.displayFont(size: 12)).foregroundStyle(theme.ink)
        }
        .frame(width: 26, height: 26)
        .scaleEffect(isCurrent ? 1 + 0.15 * segment(p, 0.6, 1) : 1)
        .shadow(color: theme.gold.opacity(isCurrent ? 0.9 * segment(p, 0.6, 1) : 0), radius: 6)
        Rectangle()
          .fill(Double(index) + 0.5 <= reach ? theme.gold : theme.ink.opacity(0.2))
          .frame(height: 3).opacity(index == count - 1 ? 0 : 1)
      }
      Text(street.name)
        .font(theme.displayFont(size: 14))
        .foregroundStyle(isCurrent ? theme.ink : theme.ink.opacity(0.7))
      boardRow(newCards(at: index))
        .opacity(cardsOpacity)
        .offset(y: 6 * (1 - cardsOpacity))
      VStack(alignment: .center, spacing: 2) {
        ForEach(Array(street.actions.enumerated()), id: \.offset) { _, action in
          Text(action)
            .frame(maxWidth: .infinity)
            .font(theme.bodyFont(size: 11, weight: .medium))
            .foregroundStyle(theme.ink.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, alignment: .center)
      .opacity(cardsOpacity)
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 8).fill(theme.gold.opacity(isCurrent ? 0.16 * segment(p, 0.6, 1) : 0))
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("explainer.bettingRoundsTimeline.\(street.name.lowercased())")
  }

  /// Cards dealt on this street (the board minus the previous street's board).
  private func newCards(at index: Int) -> [Card] {
    let board = model.streets[index].board
    let before = index > 0 ? model.streets[index - 1].board.count : 0
    return Array(board.dropFirst(min(before, board.count)))
  }

  private func boardRow(_ cards: [Card]) -> some View {
    HStack(spacing: 2) {
      if cards.isEmpty {
        Text("blinds and hole cards").font(theme.bodyFont(size: 10)).foregroundStyle(theme.mute).frame(height: 36)
      } else {
        ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
          CardView(card: card, size: .width(24))
        }
      }
    }
  }
}
