import AllInUI
import SwiftUI

struct TableScreen: View {
  let setup: TableSetup
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme

  init(setup: TableSetup) {
    self.setup = setup
  }

  var body: some View {
    VStack(spacing: 16) {
      Text("Table")
        .font(theme.displayFont(size: 36))
        .foregroundStyle(theme.parchment)
      Button("Leave") { model.router.leaveTable() }
        .buttonStyle(.fantasy(.secondary))
        .accessibilityIdentifier("table.leave")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.night)
  }
}
