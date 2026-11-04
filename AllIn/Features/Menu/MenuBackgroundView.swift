import SpriteKit
import SwiftUI
import TableKit

/// The animated drifting-cards backdrop, paused whenever the menu is not on screen.
struct MenuBackgroundView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @State private var scene: MenuBackgroundScene?
  @State private var isPaused = false

  var body: some View {
    Group {
      if let scene {
        SpriteView(scene: scene, isPaused: isPaused)
      } else {
        model.theme.night
      }
    }
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Drifting cards and coins")
    .accessibilityIdentifier("menu.background")
    .onAppear {
      if scene == nil {
        scene = MenuBackgroundScene(
          size: CGSize(width: 1120, height: 700), resolver: model.themeResolver,
          reduceMotion: model.effectiveReduceMotion(system: systemReduceMotion), seed: model.launch.seed ?? 7)
      }
      isPaused = false
    }
    .onDisappear { isPaused = true }
  }
}
