import AllInUI
import Curriculum
import SwiftUI

/// The left half of screen 5: verdict ribbon, animated explainers and the thinking text.
struct ExplainPanel: View {
  @Environment(\.theme) private var theme
  let model: ExplainPageModel

  var body: some View {
    ParchmentPanel(padding: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          VerdictRibbon(verdict: model.verdict)
          ForEach(Array(model.explainers.enumerated()), id: \.offset) { index, data in
            ExplainerHost(data: data, caption: model.captions.indices.contains(index) ? model.captions[index] : nil)
          }
          if let thinking = model.thinking, !thinking.isEmpty {
            Text("\(Text("The thinking, not the rule: ").bold())\(thinking)")
              .font(theme.bodyFont(size: 14))
              .foregroundStyle(theme.ink)
              .lineSpacing(3)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityIdentifier("explain.thinking")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }
}

/// "✓ Good call" plus the detail line.
struct VerdictRibbon: View {
  @Environment(\.theme) private var theme
  let verdict: Verdict

  var body: some View {
    HStack(spacing: 10) {
      Text(title)
        .font(theme.bodyFont(size: 14, weight: .bold))
        .foregroundStyle(textColor)
        .padding(.vertical, 5)
        .padding(.horizontal, 14)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(border, lineWidth: 1.5))
        .shadow(color: fill.opacity(0.35), radius: 4, y: 2)
        .accessibilityIdentifier("explain.verdict")
      Text(verdict.detail)
        .font(theme.bodyFont(size: 13, weight: .medium))
        .foregroundStyle(theme.mute)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("explain.verdict.detail")
      Spacer(minLength: 0)
    }
  }

  private var title: String {
    switch verdict.grade {
    case .good: "\u{2713} \(verdict.title)"
    case .smallMiss: "\u{25D0} \(verdict.title)"
    case .leak: "\u{2717} \(verdict.title)"
    }
  }

  private var fill: Color {
    switch verdict.grade {
    case .good: theme.good
    case .smallMiss: theme.gold.opacity(0.4)
    case .leak: theme.bad
    }
  }

  private var border: Color {
    switch verdict.grade {
    case .good: theme.good
    case .smallMiss: theme.gold
    case .leak: theme.bad
    }
  }

  private var textColor: Color { verdict.grade == .smallMiss ? theme.ink : .white }
}

/// The primary "Next: ..." button of the page.
struct ExplainNextButton: View {
  let label: String
  let action: @MainActor () -> Void

  var body: some View {
    Button(label) { action() }
      .buttonStyle(.fantasy(.primary))
      .accessibilityIdentifier("explain.next")
  }
}
