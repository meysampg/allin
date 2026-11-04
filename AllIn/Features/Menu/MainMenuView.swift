import AllInUI
import SwiftUI

struct MainMenuView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme

  init() {}

  var body: some View {
    ZStack(alignment: .topLeading) {
      MenuBackgroundView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
      titleBlock
        .padding(.leading, 60).padding(.top, 70)
      buttonColumn
        .frame(width: 300)
        .padding(.leading, 60).padding(.top, 220)
      TodayCard(streakDays: model.profile.streakDays) { model.router.go(.gym) }
        .frame(width: 330)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .padding(.trailing, 60).padding(.top, 220)
      ProfileBadge(profile: model.profile)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .padding(.trailing, 60).padding(.top, 70)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(theme.night)
  }

  private var titleBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("ALL-IN")
        .font(theme.displayFont(size: 54))
        .foregroundStyle(
          LinearGradient(
            colors: [theme.parchment, theme.gold, theme.gold.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        )
        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
        .accessibilityIdentifier("menu.title")
      Text("Learn to think in poker.")
        .font(theme.bodyFont(size: 15))
        .foregroundStyle(theme.mute)
        .accessibilityIdentifier("menu.subtitle")
    }
  }

  private var buttonColumn: some View {
    VStack(spacing: 10) {
      Button {
        model.router.go(.career)
      } label: {
        HStack {
          Text("▶ Continue Career").lineLimit(1).minimumScaleFactor(0.8)
          Spacer(minLength: 8)
          Tag(model.profile.careerProgress)
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.fantasy(.primary))
      .accessibilityIdentifier("menu.continueCareer")
      menuButton("Quick Play", id: "menu.quickPlay", target: .lobby)
      menuButton("Training Gym", id: "menu.gym", target: .gym)
      menuButton("Rivals", id: "menu.rivals", target: .rivals)
      menuButton("My Game", id: "menu.myGame", target: .mygame)
      menuButton("Settings", id: "menu.settings", target: .settings)
    }
  }

  private func menuButton(_ title: String, id: String, target: Screen) -> some View {
    Button {
      model.router.go(target)
    } label: {
      Text(title).frame(maxWidth: .infinity)
    }
    .buttonStyle(.fantasy(.secondary))
    .accessibilityIdentifier(id)
  }
}
