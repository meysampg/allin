import AllInUI
import SwiftUI

/// The lesson player: spot pages on the table, the explain page and the summary.
struct LessonScreen: View {
  let request: LessonRequest
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme
  @State private var controller: LessonController?

  init(request: LessonRequest) {
    self.request = request
  }

  var body: some View {
    ZStack {
      theme.night
      if let controller {
        LessonContent(controller: controller)
      }
    }
    .onAppear {
      guard controller == nil else { return }
      let created = LessonController(request: request, model: model)
      controller = created
      created.start()
    }
    .onDisappear { controller?.stop() }
  }
}

private struct LessonContent: View {
  @Environment(\.theme) private var theme
  let controller: LessonController
  @FocusState private var focused: Bool

  var body: some View {
    ZStack {
      switch controller.phase {
      case .explain(let page):
        LessonExplainPage(
          model: page, step: controller.step.label, onBack: { controller.backFromExplain() },
          onNext: { controller.next() })
      case .summary(let summary):
        LessonSummaryView(controller: controller, summary: summary, again: { controller.restart() })
      case .failed(let message):
        failure(message)
      default:
        LessonSpotView(controller: controller)
      }
    }
    .focusable(isFeedback)
    .focusEffectDisabled()
    .focused($focused)
    .onAppear { focused = true }
    .onKeyPress(.return) { advance() }
    .onKeyPress(.space) { advance() }
    .onKeyPress(.escape) {
      controller.close()
      return .handled
    }
  }

  private var isFeedback: Bool {
    if case .feedback = controller.phase { return true }
    return false
  }

  private func advance() -> KeyPress.Result {
    guard isFeedback else { return .ignored }
    controller.next()
    return .handled
  }

  private func failure(_ message: String) -> some View {
    ParchmentPanel(title: "Hoot lost the thread") {
      VStack(alignment: .leading, spacing: 12) {
        Text(message)
          .font(theme.bodyFont(size: 13))
          .foregroundStyle(theme.ink)
          .frame(width: 340, alignment: .leading)
          .accessibilityIdentifier("lesson.failed")
        HStack(spacing: 10) {
          Button("Try again") { controller.retry() }
            .buttonStyle(.fantasy(.primary))
            .accessibilityIdentifier("lesson.retry")
          Button("\u{2715} Close") { controller.close() }
            .buttonStyle(.fantasy(.secondary))
            .accessibilityIdentifier("lesson.close")
        }
      }
    }
    .fixedSize()
  }
}
