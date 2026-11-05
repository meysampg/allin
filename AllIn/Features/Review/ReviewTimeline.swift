import AllInUI
import PokerAnalysis
import PokerCore
import SwiftUI

/// Four street columns with the hero's decisions as graded tags, and the replay controls.
struct ReviewTimeline: View {
  @Environment(\.theme) private var theme
  let controller: ReviewController
  let analysis: HandAnalysis

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ForEach(Street.allCases, id: \.self) { street in
        column(street)
      }
      controls
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func column(_ street: Street) -> some View {
    let decisions = analysis.decisions.filter { $0.street == street }
    return VStack(alignment: .leading, spacing: 4) {
      Text(street.rawValue.capitalized)
        .font(theme.bodyFont(size: 14, weight: .bold))
        .foregroundStyle(theme.ink)
      if decisions.isEmpty {
        Text("—")
          .font(theme.bodyFont(size: 13))
          .foregroundStyle(theme.mute)
      } else {
        HStack(spacing: 4) {
          ForEach(decisions) { decision in
            decisionButton(decision)
          }
        }
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("review.street.\(street.rawValue)")
  }

  private func decisionButton(_ decision: ReviewedDecision) -> some View {
    let selected = controller.selection == decision.index
    return Button {
      controller.select(decision.index)
    } label: {
      Tag(decision.timelineText, style: Self.style(decision.graded.grade))
        .padding(2)
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(theme.ink, lineWidth: selected ? 3 : 0))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(decision.timelineText)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("review.decision.\(decision.index)")
  }

  private var controls: some View {
    HStack(spacing: 6) {
      Button("⏮") { controller.step(-1) }
        .disabled(!controller.canStepBack)
        .accessibilityLabel("Previous decision")
        .accessibilityIdentifier("review.prev")
      Button("▶ replay") { controller.replayHand() }
        .accessibilityIdentifier("review.play")
      Button("⏭") { controller.step(1) }
        .disabled(!controller.canStepForward)
        .accessibilityLabel("Next decision")
        .accessibilityIdentifier("review.next")
    }
    .buttonStyle(.fantasy(.small))
    .padding(.top, 14)
  }

  static func style(_ grade: Grade) -> TagStyle {
    switch grade {
    case .good: .good
    case .smallMiss: .gold
    case .leak: .bad
    }
  }
}
