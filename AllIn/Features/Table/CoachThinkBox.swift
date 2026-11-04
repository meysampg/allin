import AllInUI
import SwiftUI

/// The static "Think first" box: the same three questions before every decision.
struct CoachThinkBox: View {
  @Environment(\.theme) private var theme
  let controller: TableController

  var body: some View {
    ParchmentPanel(title: "🦉 Think first") {
      VStack(alignment: .leading, spacing: 4) {
        question(1, "What hands does \(controller.lastBettorName) bet here?")
        question(2, "How does your hand do against those?")
        question(3, "What does each of your moves achieve?")
      }
      HStack(spacing: 6) {
        Button("Show her range") {}
          .buttonStyle(.fantasy(.small))
          .disabled(true)
          .accessibilityIdentifier("table.coachBox.showRange")
        Button("I'm fine") { controller.dismissCoach() }
          .buttonStyle(.fantasy(.small))
          .accessibilityIdentifier("table.coachBox.dismiss")
      }
    }
    .frame(width: 250)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("table.coachBox")
  }

  private func question(_ number: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text("\(number).").frame(width: 14, alignment: .trailing)
      Text(text).fixedSize(horizontal: false, vertical: true)
    }
    .font(theme.bodyFont(size: 12))
    .foregroundStyle(theme.ink)
  }
}
