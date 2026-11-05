import AllInUI
import SwiftUI

/// The end of a lesson or drill: stars, what went well and the way back to the venue.
struct LessonSummaryView: View {
  @Environment(\.theme) private var theme
  let controller: LessonController
  let summary: LessonController.Summary
  let again: () -> Void

  var body: some View {
    ZStack {
      theme.night
      ParchmentPanel(title: controller.isDrill ? "Drill complete" : "Lesson complete") {
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 12) {
            StarRow(filled: summary.stars, size: 34)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel("\(summary.stars) of 3 stars")
              .accessibilityIdentifier("lesson.summary.stars")
            Text("\(summary.stars) / 3")
              .font(theme.displayFont(size: 20))
              .foregroundStyle(theme.ink)
          }
          Text(controller.title)
            .font(theme.bodyFont(size: 14, weight: .semibold))
            .foregroundStyle(theme.ink)
          VStack(alignment: .leading, spacing: 6) {
            if let puzzleGood = summary.puzzleGood {
              line(puzzleGood ? "\u{2713}" : "\u{2717}", puzzleGood ? "You solved the puzzle" : "The puzzle got away")
            }
            if summary.applyTotal > 0 {
              line(
                "\u{25CF}",
                controller.isDrill
                  ? "\(summary.applyGood) of \(summary.applyTotal) answered well"
                  : "\(summary.applyGood) of \(summary.applyTotal) spots on your own"
              )
              .accessibilityIdentifier("lesson.summary.apply")
            }
            if summary.hintsUsed > 0 && controller.hintCostsStar {
              line(
                "\u{1F4A1}",
                "\(summary.hintsUsed) \(summary.hintsUsed == 1 ? "hint" : "hints") (\u{2212}\(summary.hintsUsed)\u{2605})"
              )
            }
          }
          HStack(spacing: 10) {
            Button("Back to the venue") { controller.close() }
              .buttonStyle(.fantasy(.primary))
              .accessibilityIdentifier("lesson.summary.done")
            Button("Play again", action: again)
              .buttonStyle(.fantasy(.secondary))
              .accessibilityIdentifier("lesson.summary.again")
          }
        }
        .frame(width: 360, alignment: .leading)
      }
      .fixedSize()
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("lesson.summary")
  }

  private func line(_ mark: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(mark).frame(width: 18)
      Text(text)
    }
    .font(theme.bodyFont(size: 14))
    .foregroundStyle(theme.ink)
  }
}
