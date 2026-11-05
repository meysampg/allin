import AllInUI
import PokerAnalysis
import PokerEquity
import SwiftUI

/// The selected decision: what happened, why, what each option earns, and what to do next.
struct ReviewExplanationPanel: View {
  @Environment(\.theme) private var theme
  let controller: ReviewController
  let decision: ReviewedDecision
  let presentation: ReviewPresentation
  let onRivals: () -> Void

  var body: some View {
    ParchmentPanel(padding: 14) {
      VStack(alignment: .leading, spacing: 10) {
        Text(decision.title)
          .font(theme.bodyFont(size: 18, weight: .bold))
          .foregroundStyle(theme.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("review.explanation.title")
        Text(decision.body)
          .font(theme.bodyFont(size: 14))
          .foregroundStyle(theme.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("review.explanation.body")
        chartRow
        HStack(spacing: 8) {
          Button("Replay this spot") { controller.replaySpot() }
            .accessibilityIdentifier("review.replaySpot")
          let saved = controller.isSaved(decision)
          Button(saved ? "Added to Gym ✓" : "Add to my Gym") { controller.addToGym(decision) }
            .disabled(saved)
            .accessibilityIdentifier("review.addToGym")
          rivalButton
        }
        .buttonStyle(.fantasy(.small))
        Spacer(minLength: 0)
        Text("Judged by decision quality, not by results. You can make the right play and still lose the pot.")
          .font(theme.bodyFont(size: 12))
          .foregroundStyle(theme.mute)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("review.footnote")
      }
      .frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("review.explanation")
  }

  private var chartRow: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Average result of each option (big blinds)")
          .font(theme.bodyFont(size: 11))
          .foregroundStyle(theme.mute)
        EVBarChart(decision: decision)
      }
      if let grid = decision.focusRangeGrid, let name = decision.focusName {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(name)'s range")
            .font(theme.bodyFont(size: 11))
            .foregroundStyle(theme.mute)
          RangeGridView(range: HandRange(grid: grid), cellSize: 9, showsLabels: false)
        }
      }
    }
  }

  @ViewBuilder
  private var rivalButton: some View {
    let name = decision.focusName.map { "Notes on \($0)" } ?? "Rival notes"
    switch presentation {
    case .standalone:
      Button(name, action: onRivals)
        .accessibilityIdentifier("review.rivalNotes")
    case .overlay:
      Button(name, action: onRivals)
        .disabled(true)
        .help("Rivals open in a later update")
        .accessibilityIdentifier("review.rivalNotes")
    }
  }
}
