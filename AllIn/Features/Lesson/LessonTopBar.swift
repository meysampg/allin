import AllInUI
import SwiftUI

/// Close button, lesson title, step tag and progress bar.
struct LessonTopBar: View {
  @Environment(\.theme) private var theme
  let controller: LessonController

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Button("\u{2715}") { controller.close() }
        .buttonStyle(.fantasy(.small))
        .accessibilityLabel("Close")
        .accessibilityIdentifier("lesson.close")
      Text(controller.title)
        .font(theme.displayFont(size: 18))
        .foregroundStyle(theme.parchment)
        .lineLimit(1)
        .accessibilityIdentifier("lesson.title")
      Spacer(minLength: 0)
      if case .question(let page) = controller.phase {
        repTag(page.repLabel)
      } else if case .feedback(let page, _) = controller.phase {
        repTag(page.repLabel)
      }
      Tag(controller.stepLabel)
        .accessibilityIdentifier("lesson.step")
      Meter(value: controller.progress)
        .frame(width: 160)
        .accessibilityIdentifier("lesson.progress")
        .accessibilityValue("\(Int((controller.progress * 100).rounded()))%")
    }
    .padding(.horizontal, 12)
    .padding(.top, 10)
  }

  @ViewBuilder
  private func repTag(_ label: String?) -> some View {
    if let label {
      Tag(label, style: .gold)
        .accessibilityIdentifier("lesson.rep")
    }
  }
}
