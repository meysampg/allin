import AllInUI
import SwiftUI

struct MainMenuView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme

  init() {}

  var body: some View {
    VStack(spacing: 16) {
      Text("ALL-IN")
        .font(theme.displayFont(size: 64))
        .foregroundStyle(theme.gold)
        .accessibilityIdentifier("menu.title")
      Button("Quick Play") { model.router.go(.lobby) }
        .buttonStyle(.fantasy(.primary))
        .accessibilityIdentifier("menu.quickPlay")
      Button("Settings") { model.router.go(.settings) }
        .buttonStyle(.fantasy(.secondary))
        .accessibilityIdentifier("menu.settings")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.night)
  }
}
