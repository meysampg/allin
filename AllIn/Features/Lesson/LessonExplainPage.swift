import AllInUI
import Curriculum
import SwiftUI

/// Screen 5: why the answer works (left) and the Alchemist's Bench (right). Built by the lesson player.
struct LessonExplainPage: View {
  @Environment(\.theme) private var theme
  @Environment(AppModel.self) private var app: AppModel?
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  let model: ExplainPageModel
  let step: String
  let onBack: @MainActor () -> Void
  let onNext: @MainActor () -> Void

  init(
    model: ExplainPageModel, step: String, onBack: @escaping @MainActor () -> Void,
    onNext: @escaping @MainActor () -> Void
  ) {
    self.model = model
    self.step = step
    self.onBack = onBack
    self.onNext = onNext
  }

  private var animates: Bool {
    !(systemReduceMotion || (app?.effectiveReduceMotion(system: false) ?? false))
  }

  var body: some View {
    VStack(spacing: 12) {
      topBar
      if let setup = model.sandbox {
        GeometryReader { proxy in
          let gap: CGFloat = 14
          let left = (proxy.size.width - gap) * 0.48
          HStack(alignment: .top, spacing: gap) {
            ExplainPanel(model: model)
              .frame(width: left)
            SandboxPanel(setup: setup, nextLabel: model.nextLabel, onNext: onNext)
              .id(setup)
          }
        }
      } else {
        VStack(spacing: 12) {
          ExplainPanel(model: model)
          HStack {
            Spacer()
            ExplainNextButton(label: model.nextLabel, action: onNext)
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(theme.night)
    .environment(\.explainerAnimates, animates)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("explain.page")
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      Button("\u{2190}") { onBack() }
        .buttonStyle(.fantasy(.small))
        .accessibilityLabel("Back")
        .accessibilityIdentifier("explain.back")
      Text(model.title)
        .font(theme.displayFont(size: 20))
        .foregroundStyle(theme.parchment)
        .accessibilityIdentifier("explain.title")
      Spacer()
      Tag(step, style: .gold)
        .accessibilityIdentifier("explain.step")
    }
  }
}
