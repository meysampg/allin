import PokerCore
import SwiftUI

extension EnvironmentValues {
  /// Snapshot tests and previews set this to `false` to render the final frame of every explainer animation.
  @Entry public var explainerAnimates: Bool = true
}

/// A view whose body is a pure function of an animated progress value (0...1).
struct StagedProgress<Content: View>: View, @preconcurrency Animatable {
  var progress: Double
  let content: (Double) -> Content

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  var body: some View { content(progress) }
}

/// Runs one animation of at most `duration` seconds on appear and hands the progress to `content`.
/// Reduce motion (or `explainerAnimates == false`) shows the final frame.
struct Reveal<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.explainerAnimates) private var animates
  @State private var target = 0.0
  private let duration: Double
  private let content: (Double) -> Content

  init(duration: Double = 1.1, @ViewBuilder content: @escaping (Double) -> Content) {
    self.duration = min(duration, 1.2)
    self.content = content
  }

  var body: some View {
    let on = animates && !reduceMotion
    StagedProgress(progress: on ? target : 1, content: content)
      .onAppear {
        guard on else { return }
        withAnimation(.easeInOut(duration: duration)) { target = 1 }
      }
  }
}

/// Maps `p` in `from...to` onto 0...1.
func segment(_ p: Double, _ from: Double, _ to: Double) -> Double {
  guard to > from else { return p >= to ? 1 : 0 }
  return min(max((p - from) / (to - from), 0), 1)
}

func percentText(_ value: Double) -> String {
  "\(Int((min(max(value.isFinite ? value : 0, 0), 1) * 100).rounded()))%"
}

func cardName(_ card: Card) -> String {
  let ranks = [
    "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace",
  ]
  let suits = ["clubs", "diamonds", "hearts", "spades"]
  return "\(ranks[Int(card.rank.rawValue)]) of \(suits[Int(card.suit.rawValue)])"
}

func suitGlyph(_ suit: Suit) -> String {
  switch suit {
  case .clubs: "\u{2663}"
  case .diamonds: "\u{2666}"
  case .hearts: "\u{2665}"
  case .spades: "\u{2660}"
  }
}

func rankText(_ rank: Rank) -> String { rank == .ten ? "10" : String(rank.symbol) }

func parseCards(_ text: String) -> [Card] { (try? Card.parseList(text)) ?? [] }

/// Parchment-toned rounded backdrop shared by the explainer canvases.
struct ExplainerSurface: ViewModifier {
  @Environment(\.theme) private var theme

  func body(content: Content) -> some View {
    content
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.parchment.opacity(0.55))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.ink.opacity(0.25), lineWidth: 1)
      )
  }
}

extension View {
  func explainerSurface() -> some View { modifier(ExplainerSurface()) }

  /// Marks the view as an accessibility container with an id and an optional spoken label.
  func explainerContainer(_ id: String, label: String? = nil) -> some View {
    accessibilityElement(children: .contain)
      .accessibilityLabel(label ?? "")
      .accessibilityIdentifier(id)
  }
}
