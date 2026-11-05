import AllInUI
import SpriteKit
import SwiftUI
import TableKit

/// The table scene with its overlays: top bar, coach box, villain and pot tags, and the answer or verdict bar.
struct LessonSpotView: View {
  @Environment(\.theme) private var theme
  let controller: LessonController

  private var page: LessonController.SpotPage? {
    switch controller.phase {
    case .question(let page), .feedback(let page, _): page
    default: nil
    }
  }

  var body: some View {
    ZStack {
      SpriteView(scene: controller.scene, preferredFramesPerSecond: 60)
        .accessibilityIdentifier("lesson.scene")
      tags
      VStack(spacing: 0) {
        LessonTopBar(controller: controller)
        Spacer(minLength: 0)
        bottomBar
      }
      if let page {
        GeometryReader { proxy in
          LessonCoachPanel(controller: controller, page: page)
            .padding(.leading, 12)
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
      }
      if controller.phase == .preparing {
        LessonPreparingOverlay()
      }
    }
    .aspectRatio(LessonLayout.ratio, contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var bottomBar: some View {
    switch controller.phase {
    case .question(let page):
      LessonAnswerBar(controller: controller, page: page)
        .id(controller.pageID)
    case .feedback(let page, let grade):
      LessonVerdictBar(controller: controller, page: page, grade: grade)
    default:
      EmptyView()
    }
  }

  /// "Vexa · bets 50" beside the bettor's chips, "POT 150 (+50)" over the pot caption of the scene.
  @ViewBuilder
  private var tags: some View {
    if let overlay = controller.overlay, page != nil {
      GeometryReader { proxy in
        let width = proxy.size.width
        let height = proxy.size.height
        let positions = SeatLayout.positions(seatCount: overlay.seatCount, heroSeat: overlay.heroSeat)
        if let tag = overlay.villainTag, let seat = overlay.villainSeat, let point = positions[seat] {
          let chips = SeatLayout.betPoint(for: point)
          pill(tag, fill: theme.night, text: theme.parchment)
            .position(x: chips.x * width + 100 / 1120 * width, y: chips.y * height + 6 / 700 * height)
            .accessibilityIdentifier("lesson.villainTag")
        }
        pill(overlay.potText, fill: theme.panel, text: theme.ink)
          .position(
            x: SeatLayout.potPoint.x * width, y: (SeatLayout.potPoint.y + 26 / 700) * height
          )
          .accessibilityIdentifier("lesson.pot")
      }
      .allowsHitTesting(false)
    }
  }

  /// Opaque, so the pot tag also hides the scene's own "POT 100" caption underneath.
  private func pill(_ text: String, fill: Color, text color: Color) -> some View {
    Text(text)
      .font(theme.bodyFont(size: 13, weight: .bold))
      .foregroundStyle(color)
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .background(Capsule().fill(fill))
      .overlay(Capsule().strokeBorder(theme.gold, lineWidth: 1.5))
      .fixedSize()
  }
}

enum LessonLayout {
  static let ratio: CGFloat = 1120.0 / 700.0
}

/// A spinner on a parchment note, shown if a spot takes more than a moment to solve.
struct LessonPreparingOverlay: View {
  @Environment(\.theme) private var theme
  @State private var visible = false

  var body: some View {
    ZStack {
      if visible {
        Color.black.opacity(0.35)
        ParchmentPanel {
          HStack(spacing: 12) {
            ProgressView()
              .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
              Text("\u{1F989} Hoot is setting the table\u{2026}")
                .font(theme.bodyFont(size: 14, weight: .bold))
                .foregroundStyle(theme.ink)
              Text("Shuffling a fresh hand for you")
                .font(theme.bodyFont(size: 12))
                .foregroundStyle(theme.ink.opacity(0.8))
            }
          }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lesson.preparing")
      }
    }
    .task {
      try? await Task.sleep(for: .milliseconds(150))
      visible = true
    }
  }
}
