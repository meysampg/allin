import AllInUI
import PokerHost
import SwiftUI

struct LobbyOptionsPanel: View {
  @Bindable var model: LobbyModel
  let onSitDown: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    ParchmentPanel(title: "Options", padding: 14) {
      VStack(spacing: 12) {
        row("Stakes / buy-in") { Tag("1/2 · 200 gold").accessibilityIdentifier("lobby.option.stakes") }
        row("Coach") {
          TagPicker(
            options: [
              TagOption(.questions, label: "Questions", id: "questions"),
              TagOption(.review, label: "Review", id: "review"),
              TagOption(.off, label: "Off", id: "off"),
            ], selection: $model.coach, idPrefix: "lobby.option.coach")
        }
        row("HUD") {
          TagPicker(
            options: [
              TagOption(.off, label: "Off", id: "off"),
              TagOption(.basic, label: "Basic", id: "basic"),
              TagOption(.full, label: "Full", id: "full"),
            ], selection: $model.hud, idPrefix: "lobby.option.hud")
        }
        row("Speed") {
          TagPicker(
            options: [
              TagOption(GameSpeed.relaxed, label: "Relaxed", id: "relaxed"),
              TagOption(GameSpeed.normal, label: "Normal", id: "normal"),
              TagOption(GameSpeed.turbo, label: "Turbo", id: "turbo"),
            ], selection: $model.speed, idPrefix: "lobby.option.speed")
        }
        Spacer(minLength: 0)
        HStack {
          Spacer()
          Button("Sit down", action: onSitDown)
            .buttonStyle(.fantasy(.primary))
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("lobby.sitDown")
        }
      }
      .frame(maxHeight: .infinity)
    }
  }

  private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
    HStack {
      Text(label).font(theme.bodyFont(size: 14)).foregroundStyle(theme.ink)
      Spacer(minLength: 12)
      control()
    }
  }
}
