import AllInUI
import SwiftUI

struct TodayCard: View {
  let streakDays: Int
  let onStartWarmup: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    ParchmentPanel(title: "Today", padding: 14) {
      VStack(alignment: .leading, spacing: 10) {
        row(Tag("5 min"), "Warm-up: 10 spots from your weakest skill")
        row(Tag("Next"), "Lesson: \"Why position is power\"")
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Tag("Streak")
          Image(systemName: "flame.fill").foregroundStyle(theme.gold)
          Text("\(streakDays) days").font(theme.bodyFont(size: 13)).foregroundStyle(theme.ink)
        }
        Button("Start warm-up", action: onStartWarmup)
          .buttonStyle(.fantasy(.small))
          .padding(.top, 2)
          .accessibilityIdentifier("menu.today.startWarmup")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("menu.today")
  }

  private func row(_ tag: Tag, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      tag
      Text(text)
        .font(theme.bodyFont(size: 13))
        .foregroundStyle(theme.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
