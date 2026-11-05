import AllInUI
import SwiftUI

/// Stub of the lesson player (replaced by M5.6): shows the title and a close button.
struct LessonScreen: View {
  let request: LessonRequest
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme

  init(request: LessonRequest) {
    self.request = request
  }

  private var title: String {
    let library = model.curriculum.library
    switch request.content {
    case .lesson(let id): return library?.lesson(id)?.title ?? "Lesson"
    case .drill(let id): return library?.drill(id)?.title ?? "Drill"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Button("\u{2715}") { model.router.closeLesson() }
          .buttonStyle(.fantasy(.small))
          .accessibilityLabel("Close")
          .accessibilityIdentifier("lesson.close")
        Text(title)
          .font(theme.bodyFont(size: 17, weight: .bold))
          .foregroundStyle(theme.parchment)
          .accessibilityIdentifier("lesson.title")
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(theme.night)
  }
}
