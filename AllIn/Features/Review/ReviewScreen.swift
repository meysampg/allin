import AllInUI
import PokerAnalysis
import SwiftUI

/// Screen 7: the hand's timeline, a mini table replay, and the explanation of the selected decision.
struct ReviewScreen: View {
  let request: ReviewRequest
  let presentation: ReviewPresentation
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @State private var controller: ReviewController?

  init(request: ReviewRequest, presentation: ReviewPresentation) {
    self.request = request
    self.presentation = presentation
  }

  var body: some View {
    ZStack {
      theme.night
      if let controller {
        ReviewContent(controller: controller, presentation: presentation, back: back, openRivals: openRivals)
          .aspectRatio(ReviewLayout.ratio, contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear {
      guard controller == nil else { return }
      let created = ReviewController(request: request, model: model, systemReduceMotion: systemReduceMotion)
      controller = created
      created.start()
    }
    .onDisappear { controller?.stop() }
  }

  private func back() {
    switch presentation {
    case .standalone: model.router.backToMenu()
    case .overlay(let onBack): onBack()
    }
  }

  private func openRivals() {
    model.router.go(.rivals)
  }
}

enum ReviewLayout {
  static let ratio: CGFloat = 1120.0 / 700.0
}

private struct ReviewContent: View {
  @Environment(\.theme) private var theme
  let controller: ReviewController
  let presentation: ReviewPresentation
  let back: () -> Void
  let openRivals: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    GeometryReader { proxy in
      let gap: CGFloat = 16
      let usable = max(0, proxy.size.width - 3 * gap)
      let tableWidth = usable * 520 / 1060
      let explanationWidth = usable - tableWidth
      let bodyHeight = max(0, proxy.size.height - 160 - gap)
      ZStack(alignment: .topLeading) {
        header
          .padding(.leading, 16)
          .padding(.top, 12)
        timeline
          .frame(height: 90)
          .padding(.horizontal, 16)
          .padding(.top, 52)
        ReviewTableView(controller: controller)
          .frame(width: tableWidth, height: bodyHeight)
          .padding(.leading, 16)
          .padding(.top, 160)
        explanation
          .frame(width: explanationWidth, height: bodyHeight)
          .padding(.leading, 16 + tableWidth + gap)
          .padding(.top, 160)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .focusable()
    .focusEffectDisabled()
    .focused($focused)
    .onAppear { focused = true }
    .onKeyPress(.leftArrow) {
      controller.step(-1)
      return .handled
    }
    .onKeyPress(.rightArrow) {
      controller.step(1)
      return .handled
    }
    .onKeyPress(.escape) {
      back()
      return .handled
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Button(backTitle, action: back)
        .buttonStyle(.fantasy(.small))
        .accessibilityIdentifier("review.back")
      Text("Hand #\(controller.handNumber) review")
        .font(theme.displayFont(size: 18))
        .foregroundStyle(theme.parchment)
        .accessibilityIdentifier("review.title")
      if let analysis = controller.analysis {
        Tag(analysis.headline)
          .accessibilityIdentifier("review.summary")
        if let luck = analysis.luckText {
          Tag(luck, style: .gold)
            .accessibilityIdentifier("review.luck")
        }
      }
    }
  }

  private var backTitle: String {
    switch presentation {
    case .standalone: "← Menu"
    case .overlay: "← Back to table"
    }
  }

  private var timeline: some View {
    ParchmentPanel(padding: 10) {
      switch controller.phase {
      case .loading, .grading:
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text("🦉 Hoot is studying this hand…")
            .font(theme.bodyFont(size: 14))
            .foregroundStyle(theme.ink)
            .accessibilityIdentifier("review.grading")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      case .failed(let message):
        Text(message)
          .font(theme.bodyFont(size: 14))
          .foregroundStyle(theme.ink)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .accessibilityIdentifier("review.failed")
      case .ready:
        if let analysis = controller.analysis, !analysis.decisions.isEmpty {
          ReviewTimeline(controller: controller, analysis: analysis)
        } else {
          Text("You didn't act in this hand.")
            .font(theme.bodyFont(size: 14))
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityIdentifier("review.empty")
        }
      }
    }
    .frame(maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("review.timeline")
  }

  @ViewBuilder
  private var explanation: some View {
    if let decision = controller.selectedDecision {
      ReviewExplanationPanel(
        controller: controller, decision: decision, presentation: presentation, onRivals: openRivals)
    } else {
      ParchmentPanel(padding: 14) {
        Text(controller.phase == .ready ? "Nothing to explain here." : "The explanation appears when grading finishes.")
          .font(theme.bodyFont(size: 14))
          .foregroundStyle(theme.mute)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(maxHeight: .infinity)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("review.explanation")
    }
  }
}
