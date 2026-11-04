import AllInUI
import SwiftUI

/// The opponent's inferred range, drawn above the coach box.
struct CoachRangePanel: View {
  @Environment(\.theme) private var theme
  let controller: TableController

  var body: some View {
    let state = controller.coach.rangeState
    if state != .hidden {
      ParchmentPanel(padding: 10) {
        VStack(alignment: .leading, spacing: 6) {
          header(state)
          content(state)
        }
      }
      .frame(width: 250)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("table.coachRange")
    }
  }

  private func header(_ state: CoachController.RangeState) -> some View {
    HStack {
      Text(title(state))
        .font(theme.displayFont(size: 15))
        .foregroundStyle(theme.ink)
        .accessibilityIdentifier("table.coachRange.title")
      Spacer(minLength: 0)
      Button("×") { controller.coach.hideRange() }
        .buttonStyle(.fantasy(.small))
        .accessibilityLabel("Close range")
        .accessibilityIdentifier("table.coachRange.close")
    }
  }

  private func title(_ state: CoachController.RangeState) -> String {
    switch state {
    case .loading(let name): "\(name)'s range"
    case .shown(let shown): "\(shown.name)'s range"
    case .failed, .hidden: "Range"
    }
  }

  @ViewBuilder
  private func content(_ state: CoachController.RangeState) -> some View {
    switch state {
    case .hidden:
      EmptyView()
    case .loading(let name):
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Reading \(name)…")
          .font(theme.bodyFont(size: 12))
          .foregroundStyle(theme.ink)
          .accessibilityIdentifier("table.coachRange.loading")
      }
    case .shown(let shown):
      RangeGridView(range: shown.range, dead: shown.dead, cellSize: 17)
      Text(RangeGridModel(range: shown.range, dead: shown.dead).summary)
        .font(theme.bodyFont(size: 12, weight: .semibold))
        .foregroundStyle(theme.ink)
      Text("read from \(shown.actionsRead) \(shown.actionsRead == 1 ? "action" : "actions")")
        .font(theme.bodyFont(size: 11))
        .foregroundStyle(theme.mute)
      if shown.inconsistent {
        Text("Their play surprised me; this is a rough read.")
          .font(theme.bodyFont(size: 11))
          .foregroundStyle(theme.mute)
          .fixedSize(horizontal: false, vertical: true)
      }
    case .failed(let message):
      Text(message)
        .font(theme.bodyFont(size: 12))
        .foregroundStyle(theme.mute)
    }
  }
}
