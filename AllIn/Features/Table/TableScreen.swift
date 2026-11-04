import AllInUI
import SwiftUI

struct TableScreen: View {
  let setup: TableSetup
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @State private var controller: TableController?

  init(setup: TableSetup) {
    self.setup = setup
  }

  var body: some View {
    ZStack {
      theme.night
      if let controller {
        TableContent(controller: controller)
      }
    }
    .onAppear {
      guard controller == nil else { return }
      let created = TableController(setup: setup, model: model, systemReduceMotion: systemReduceMotion)
      controller = created
      created.start()
    }
    .onDisappear { controller?.stop() }
  }
}

/// The 1120×700 layout, scaled to fit the window; the scene and the overlays share one coordinate space.
private struct TableContent: View {
  @Environment(\.theme) private var theme
  let controller: TableController

  var body: some View {
    ZStack {
      TableSceneView(controller: controller)
      VStack(spacing: 0) {
        TableTopBar(controller: controller)
        Spacer(minLength: 0)
        if controller.phase == .handOver {
          Button("Deal next hand · Space") { controller.nextHand() }
            .buttonStyle(.fantasy(.primary))
            .padding(.bottom, 10)
            .accessibilityIdentifier("table.nextHand")
        }
        ActionBar(controller: controller)
      }
      if controller.coachVisible, controller.coach.hintLevel != .off {
        GeometryReader { proxy in
          CoachPanel(controller: controller)
            .padding(.leading, 12)
            .padding(.top, proxy.size.height * 0.56)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
      if controller.coach.rangeState != .hidden {
        CoachRangePanel(controller: controller)
          .padding(.leading, 12)
          .padding(.top, 60)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      if controller.isMenuOpen {
        TableMenuOverlay(controller: controller)
      }
    }
    .aspectRatio(TableSceneAspect.ratio, contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .tableKeyHandling(controller)
    .focusedSceneValue(\.tableActions, controller.actions)
  }
}

private enum TableSceneAspect {
  static let ratio: CGFloat = 1120.0 / 700.0
}
