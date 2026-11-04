import AllInUI
import SwiftUI

struct ProfileBadge: View {
  let profile: PlayerProfile
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: 10) {
      AvatarMedallion(characterID: "you", size: 46)
      VStack(alignment: .leading, spacing: 2) {
        Text(profile.name)
          .font(theme.bodyFont(size: 15, weight: .bold))
          .foregroundStyle(theme.parchment)
        Text("Rank: \(profile.rank) · \(profile.gold) gold")
          .font(theme.bodyFont(size: 12))
          .foregroundStyle(theme.mute)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("menu.profile")
  }
}
