import AllInUI
import SwiftUI

/// The "Think first" box: the same questions before every decision, plus the range button.
struct CoachPanel: View {
  @Environment(\.theme) private var theme
  let controller: TableController

  var body: some View {
    let focusName = controller.coachFocusName
    ParchmentPanel(title: "🦉 Think first") {
      VStack(alignment: .leading, spacing: 4) {
        question(1, "What hands does \(focusName ?? "the table") bet here?")
        if controller.coach.hintLevel == .full {
          question(2, "How does \(controller.heroShortName) do against those?")
          question(3, "What does each of your moves achieve?")
        }
      }
      HStack(spacing: 6) {
        Button(focusName.map { "Show \($0)'s range" } ?? "Show their range") { controller.showCoachRange() }
          .buttonStyle(.fantasy(.small))
          .disabled(!controller.canShowCoachRange)
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
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("table.coachBox.question.\(number)")
  }
}
