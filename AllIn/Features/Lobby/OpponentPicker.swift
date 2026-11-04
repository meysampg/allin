import AllInUI
import SwiftUI

struct OpponentPicker: View {
  let model: LobbyModel
  @Environment(AppModel.self) private var app
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ForEach(TableSetup.lobbyRoster, id: \.self) { id in
        let character = app.character(id)
        item(
          id: id, name: character?.name ?? id.capitalized, tag: character?.style ?? "", isOn: model.isSelected(id)
        ) { model.toggleOpponent(id) }
      }
      item(id: "random", name: "Random", tag: "random mix", isOn: model.randomMix) { model.toggleRandomMix() }
    }
  }

  private func item(id: String, name: String, tag: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        AvatarMedallion(characterID: id, name: name, size: 54, isDimmed: !isOn)
        Tag(tag, style: isOn ? .gold : .plain).opacity(isOn ? 1 : 0.5)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(name), \(tag)")
    .accessibilityAddTraits(isOn ? .isSelected : [])
    .accessibilityIdentifier("lobby.opponent.\(id)")
  }
}
