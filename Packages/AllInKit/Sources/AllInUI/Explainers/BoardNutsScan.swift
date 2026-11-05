import PokerCore
import SwiftUI

/// What the board allows, and the best hand anyone could hold.
public struct NutsScanModel: Sendable, Hashable {
  public var board: [Card]
  public var nuts: String
  public var nutCards: [Card]
  public var flushPossible: Bool
  public var straightPossible: Bool
  public var fullHousePossible: Bool

  public init(
    board: [Card], nuts: String, nutCards: [Card], flushPossible: Bool, straightPossible: Bool,
    fullHousePossible: Bool
  ) {
    self.board = board
    self.nuts = nuts
    self.nutCards = nutCards
    self.flushPossible = flushPossible
    self.straightPossible = straightPossible
    self.fullHousePossible = fullHousePossible
  }
}

public struct BoardNutsScanView: View {
  @Environment(\.theme) private var theme
  private let model: NutsScanModel

  public init(model: NutsScanModel) { self.model = model }

  public var body: some View {
    Reveal { p in
      VStack(spacing: 12) {
        board(progress: p)
        HStack(spacing: 10) {
          rune("Flush", "drop.fill", model.flushPossible, lit: segment(p, 0.5, 0.7))
          rune("Straight", "arrow.up.right", model.straightPossible, lit: segment(p, 0.65, 0.85))
          rune("Full house", "house.fill", model.fullHousePossible, lit: segment(p, 0.8, 1))
        }
        HStack(spacing: 8) {
          Text("The nuts:").font(theme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(theme.mute)
          Text(model.nuts).font(theme.displayFont(size: 15)).foregroundStyle(theme.ink)
            .accessibilityIdentifier("explainer.boardNutsScan.nuts")
          HStack(spacing: 2) {
            ForEach(Array(model.nutCards.enumerated()), id: \.offset) { _, card in
              CardView(card: card, size: .width(22))
            }
          }
        }
        .opacity(segment(p, 0.8, 1))
      }
    }
    .frame(maxWidth: .infinity)
    .explainerSurface()
    .explainerContainer("explainer.boardNutsScan", label: "Board scan. The nuts: \(model.nuts)")
  }

  private func board(progress p: Double) -> some View {
    let scan = segment(p, 0, 0.55)
    return ZStack {
      HStack(spacing: 6) {
        ForEach(Array(model.board.enumerated()), id: \.offset) { _, card in CardView(card: card) }
      }
      GeometryReader { proxy in
        let x = proxy.size.width * scan
        Rectangle()
          .fill(
            LinearGradient(
              colors: [theme.rune.opacity(0), theme.rune.opacity(0.85), theme.rune.opacity(0)],
              startPoint: .leading, endPoint: .trailing)
          )
          .frame(width: 28)
          .offset(x: x - 14)
          .opacity(scan > 0 && scan < 1 ? 1 : 0)
      }
      .allowsHitTesting(false)
    }
    .frame(height: 62)
    .clipped()
  }

  private func rune(_ name: String, _ symbol: String, _ possible: Bool, lit: Double) -> some View {
    let on = possible ? lit : 0
    return VStack(spacing: 4) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(possible ? theme.gold.opacity(0.25 + 0.55 * on) : theme.mute.opacity(0.12))
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(possible ? theme.gold : theme.mute.opacity(0.5), lineWidth: possible ? 2 : 1.5)
        Image(systemName: symbol)
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(possible ? theme.ink : theme.mute.opacity(0.7))
      }
      .frame(width: 52, height: 46)
      .shadow(color: theme.gold.opacity(0.8 * on), radius: 7)
      .scaleEffect(1 + 0.08 * on)
      Text(name).font(theme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(possible ? theme.ink : theme.mute)
      Text(possible ? "possible" : "not possible")
        .font(theme.bodyFont(size: 10))
        .foregroundStyle(possible ? theme.ink.opacity(0.8) : theme.mute)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name): \(possible ? "possible" : "not possible")")
    .accessibilityIdentifier("explainer.boardNutsScan.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))")
  }
}
