import AllInUI
import SwiftUI

struct TableMenuOverlay: View {
  @Environment(\.theme) private var theme
  let controller: TableController

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
        .contentShape(Rectangle())
        .onTapGesture { controller.closeMenu() }
      ParchmentPanel(title: "Table menu", padding: 18) {
        VStack(spacing: 10) {
          Button("Resume") { controller.closeMenu() }
            .buttonStyle(.fantasy(.primary))
            .accessibilityIdentifier("table.resume")
          Button("Leave table") { controller.leave() }
            .buttonStyle(.fantasy(.secondary))
            .accessibilityIdentifier("table.leave")
        }
        .frame(maxWidth: .infinity)
      }
      .frame(width: 260)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("table.menuOverlay")
  }
}
