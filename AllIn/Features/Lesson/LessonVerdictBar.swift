import AllInUI
import Curriculum
import PokerAnalysis
import SwiftUI

/// After the answer: the verdict, the numbers behind it and the Next button.
struct LessonVerdictBar: View {
  @Environment(\.theme) private var theme
  let controller: LessonController
  let page: LessonController.SpotPage
  let grade: SpotGrade

  private var tint: Color {
    switch grade.grade {
    case .good: theme.good
    case .smallMiss: theme.gold
    case .leak: theme.bad
    }
  }

  var body: some View {
    HStack(spacing: 14) {
      RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 6, height: 52)
      VStack(alignment: .leading, spacing: 2) {
        Text(grade.verdictTitle)
          .font(theme.displayFont(size: 17))
          .foregroundStyle(tint)
          .accessibilityIdentifier("lesson.verdict")
        Text(grade.verdictDetail)
          .font(theme.bodyFont(size: 13))
          .foregroundStyle(theme.parchment)
          .lineLimit(2)
          .accessibilityIdentifier("lesson.verdict.detail")
        if let list = evList {
          Text(list)
            .font(theme.bodyFont(size: 11, weight: .medium))
            .foregroundStyle(theme.parchment.opacity(0.7))
            .lineLimit(1)
            .accessibilityIdentifier("lesson.evList")
        }
      }
      Spacer(minLength: 0)
      Button("Next \u{2192}") { controller.next() }
        .buttonStyle(.fantasy(.primary))
        .accessibilityIdentifier("lesson.next")
    }
    .padding(.horizontal, 14)
    .frame(height: 78)
    .frame(maxWidth: .infinity)
    .background(theme.night.opacity(0.92))
    .overlay(alignment: .top) { Rectangle().fill(tint.opacity(0.8)).frame(height: 2) }
  }

  /// "Fold 0.0 · Call +1.8 · Raise to 150 \u{2212}0.4" for the EV methods.
  private var evList: String? {
    let priced = page.spot.solution.options.filter { $0.evBB != nil }
    guard priced.count >= 2 else { return nil }
    return priced.map { "\($0.label) \(Self.signed($0.evBB ?? 0))" }.joined(separator: "  \u{00B7}  ")
  }

  private static func signed(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == 0 { return "0.0" }
    return (rounded > 0 ? "+" : "\u{2212}") + String(format: "%.1f", abs(rounded))
  }
}
