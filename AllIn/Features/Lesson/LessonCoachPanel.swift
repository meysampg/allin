import AllInUI
import SwiftUI

/// Top-left box: Hoot's situation text and the bold question, then the hint once it is asked for.
struct LessonCoachPanel: View {
  @Environment(\.theme) private var theme
  let controller: LessonController
  let page: LessonController.SpotPage

  var body: some View {
    ParchmentPanel(title: page.showsCoach ? "\u{1F989} Hoot" : nil) {
      VStack(alignment: .leading, spacing: 8) {
        if page.showsCoach, let text = page.coachText {
          Text(text)
            .font(theme.bodyFont(size: 13))
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("lesson.coach.text")
        }
        Text(page.spot.prompt)
          .font(theme.bodyFont(size: 14, weight: .bold))
          .foregroundStyle(theme.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("lesson.prompt")
        if controller.hintShown {
          Text("\u{1F4A1} \(page.spot.solution.hint)")
            .font(theme.bodyFont(size: 12, weight: .medium))
            .foregroundStyle(theme.ink)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.gold.opacity(0.25)))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("lesson.coach.hint")
        }
      }
    }
    .frame(width: 250)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(page.showsCoach ? "lesson.coach" : "lesson.promptBox")
  }
}
