import AllInUI
import Curriculum
import SwiftUI

/// The venue's skill meters as rune bars.
struct ChapterSkillsPanel: View {
  let meters: [(meter: VenueMeter, value: Double)]
  @Environment(\.theme) private var theme

  var body: some View {
    ParchmentPanel(title: "Chapter skills", padding: 14) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(meters, id: \.meter.id) { entry in
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(entry.meter.name)
                .font(theme.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(theme.ink)
              Spacer(minLength: 0)
              Text("\(Int((entry.value * 100).rounded()))%")
                .font(theme.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("venue.meter.\(entry.meter.id)")
            }
            Meter(value: entry.value)
              .accessibilityHidden(true)
          }
        }
      }
      Text("The meters fill from how well you decide in drills and play, not from how many lessons you finish.")
        .font(theme.bodyFont(size: 12))
        .foregroundStyle(theme.ink.opacity(0.75))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)
        .accessibilityIdentifier("venue.skillsNote")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("venue.skills")
  }
}
