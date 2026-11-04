import AllInUI
import SwiftUI

struct LobbyView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.theme) private var theme
  @State private var lobby = LobbyModel()

  init() {}

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Button("← Menu") { app.router.backToMenu() }
          .buttonStyle(.fantasy(.small))
          .accessibilityIdentifier("lobby.back")
        Text("Quick Play")
          .font(theme.bodyFont(size: 17, weight: .bold))
          .foregroundStyle(theme.parchment)
          .accessibilityIdentifier("lobby.title")
      }
      .padding(.top, 12)
      HStack(alignment: .top, spacing: 14) {
        ForEach(TableSetup.Format.allCases, id: \.self) { format in
          FormatCard(format: format, isSelected: lobby.format == format) { lobby.selectFormat(format) }
        }
      }
      .padding(.top, 20)
      HStack(alignment: .top, spacing: 24) {
        opponentsPanel.frame(width: 540)
        Spacer(minLength: 0)
        LobbyOptionsPanel(model: lobby) {
          app.router.startTable(lobby.makeSetup(seed: app.newSessionSeed()))
        }
        .frame(width: 500)
      }
      .frame(maxHeight: .infinity)
      .padding(.top, 20)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(theme.night)
    .onAppear { lobby.speed = app.settings.speed }
  }

  private var opponentsPanel: some View {
    ParchmentPanel(title: "Opponents", padding: 14) {
      OpponentPicker(model: lobby)
      HStack(spacing: 10) {
        Text("Table strength").font(theme.bodyFont(size: 14)).foregroundStyle(theme.ink)
        Slider(value: $lobby.strength, in: 0...1)
          .frame(maxWidth: 240)
          .accessibilityLabel("Table strength")
          .accessibilityIdentifier("lobby.strength")
        Tag("Matches your level")
      }
      .padding(.top, 8)
      Spacer(minLength: 0)
    }
    .frame(maxHeight: .infinity)
  }
}
