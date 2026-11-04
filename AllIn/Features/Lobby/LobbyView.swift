import AllInUI
import SwiftUI

struct LobbyView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme

  init() {}

  var body: some View {
    VStack(spacing: 16) {
      Text("Quick Play")
        .font(theme.displayFont(size: 36))
        .foregroundStyle(theme.gold)
        .accessibilityIdentifier("lobby.title")
      Button("← Menu") { model.router.backToMenu() }
        .buttonStyle(.fantasy(.small))
        .accessibilityIdentifier("lobby.back")
      Button("Sit down") { model.router.startTable(.demo(seed: model.newSessionSeed())) }
        .buttonStyle(.fantasy(.primary))
        .accessibilityIdentifier("lobby.sitDown")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.night)
  }
}
