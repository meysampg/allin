import AllInUI
import Curriculum
import PokerCore
import PokerEquity
import SwiftUI

/// "Your decision:", the inputs for the spot's question type, a spacer and the hint button.
struct LessonAnswerBar: View {
  @Environment(\.theme) private var theme
  @Environment(AppModel.self) private var model
  let controller: LessonController
  let page: LessonController.SpotPage

  @State private var chosen: Set<String> = []
  @State private var numberText = ""
  @State private var cards: [Card] = []
  @State private var weights: [[Float]] = Array(repeating: Array(repeating: 0, count: 13), count: 13)

  private var solution: SpotSolution { page.spot.solution }
  private var kind: LessonInputKind { LessonInputKind(solution) }

  var body: some View {
    VStack(alignment: .trailing, spacing: 0) {
      switch kind {
      case .cards(let limit):
        LessonCardsPanel(cards: $cards, limit: limit, dead: dead, fourColor: model.settings.fourColorDeck)
          .padding(.trailing, 14)
          .padding(.bottom, 8)
      case .range:
        LessonRangePanel(weights: $weights)
          .padding(.trailing, 14)
          .padding(.bottom, 8)
      default:
        EmptyView()
      }
      bar
    }
  }

  private var bar: some View {
    HStack(spacing: 12) {
      Text("Your decision:")
        .font(theme.bodyFont(size: 14, weight: .semibold))
        .foregroundStyle(theme.parchment.opacity(0.8))
        .accessibilityIdentifier("lesson.decisionLabel")
      inputs
      Spacer(minLength: 0)
      Button(controller.hintCostsStar ? "\u{1F4A1} Hint (\u{2212}1\u{2605})" : "\u{1F4A1} Hint") {
        controller.showHint()
      }
      .buttonStyle(.fantasy(.small))
      .disabled(controller.hintShown)
      .accessibilityIdentifier("lesson.hint")
    }
    .padding(.horizontal, 14)
    .frame(height: 78)
    .frame(maxWidth: .infinity)
    .background(theme.night.opacity(0.92))
    .overlay(alignment: .top) { Rectangle().fill(theme.gold.opacity(0.7)).frame(height: 2) }
  }

  @ViewBuilder
  private var inputs: some View {
    switch kind {
    case .single:
      LessonOptionButtons(
        options: solution.options, multiple: false, primaryIndex: primaryIndex, chosen: .constant([]),
        answer: { controller.submit(.option($0)) })
    case .multiple:
      LessonOptionButtons(
        options: solution.options, multiple: true, primaryIndex: nil, chosen: $chosen, answer: { _ in })
      LessonSubmitButton(enabled: !chosen.isEmpty) { controller.submit(.options(chosen)) }
    case .number:
      LessonNumberInput(text: $numberText) {
        if let value = Int(numberText) { controller.submit(.number(value)) }
      }
    case .cards(let limit):
      Text(selectionText(limit: limit))
        .font(theme.bodyFont(size: 13))
        .foregroundStyle(theme.parchment)
      LessonSubmitButton(enabled: limit.map { cards.count == $0 } ?? !cards.isEmpty) {
        controller.submit(.cards(cards))
      }
    case .range:
      Text("Click the hands \(solution.bindings["villain"] ?? "they") would play")
        .font(theme.bodyFont(size: 13))
        .foregroundStyle(theme.parchment)
      LessonSubmitButton(enabled: weights.contains { $0.contains { $0 > 0 } }) {
        controller.submit(.range(HandRange(grid: weights)))
      }
    }
  }

  /// The middle action is the suggested one, as in the wireframe.
  private var primaryIndex: Int? {
    guard solution.question == .action, solution.options.count >= 3 else { return nil }
    return solution.options.count / 2
  }

  private var dead: CardSet {
    let hero = solution.heroCards
    let board = solution.boardCards
    switch solution.method {
    case .bestFive: return CardSet(hero + board).complement
    case .nuts: return CardSet(board)
    case .outs: return CardSet(hero + board)
    default: return CardSet()
    }
  }

  private func selectionText(limit: Int?) -> String {
    let chosen = cards.isEmpty ? "none yet" : cards.map(\.description).joined(separator: " ")
    return limit.map { "Picked \(cards.count) / \($0): \(chosen)" } ?? "Picked: \(chosen)"
  }
}
