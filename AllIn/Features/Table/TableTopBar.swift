import AllInUI
import SwiftUI

struct TableTopBar: View {
  let controller: TableController

  var body: some View {
    let setup = controller.setup
    HStack(alignment: .center, spacing: 8) {
      Button("☰") { controller.toggleMenu() }
        .buttonStyle(.fantasy(.small))
        .accessibilityLabel("Table menu")
        .accessibilityIdentifier("table.menu")
      Tag(formatText(setup))
        .accessibilityIdentifier("table.format")
      Tag("Hand #\(max(1, controller.handNumber))")
        .accessibilityIdentifier("table.handNumber")
      Spacer(minLength: 0)
      Tag("🦉 Coach: \(coachText(setup.coach))", style: setup.coach == .off ? .muted : .gold)
        .accessibilityIdentifier("table.coach")
      Tag("HUD: \(setup.hud.rawValue)")
        .accessibilityIdentifier("table.hud")
      Button("Last hand ↺") { controller.openLastHand() }
        .buttonStyle(.fantasy(.small))
        .disabled(controller.lastHandKey == nil)
        .accessibilityIdentifier("table.lastHand")
    }
    .padding(.horizontal, 12)
    .padding(.top, 10)
  }

  private func formatText(_ setup: TableSetup) -> String {
    let blinds = "\(setup.smallBlind)/\(setup.bigBlind)"
    switch setup.format {
    case .cash6Max: return "Cash 6-max · \(blinds)"
    case .headsUp: return "Heads-Up · \(blinds)"
    default: return "\(setup.format.title) · \(blinds)"
    }
  }

  private func coachText(_ mode: TableSetup.CoachMode) -> String {
    switch mode {
    case .questions: "ON"
    case .review: "Review"
    case .off: "OFF"
    }
  }
}
