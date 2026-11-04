import AllInUI
import SwiftUI

struct PlaceholderScreen: View {
  let screen: Screen
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme

  init(screen: Screen) {
    self.screen = screen
  }

  var body: some View {
    ZStack {
      theme.night.ignoresSafeArea()
      ParchmentPanel(title: screen.title, padding: 24) {
        VStack(spacing: 16) {
          Text("Opens in a later update.")
            .font(theme.bodyFont(size: 16))
            .foregroundStyle(theme.ink)
          Button("← Menu") { model.router.backToMenu() }
            .buttonStyle(.fantasy(.small))
            .accessibilityIdentifier("placeholder.back")
        }
        .frame(minWidth: 320)
      }
      .fixedSize()
    }
  }
}
