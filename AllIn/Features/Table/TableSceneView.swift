import SpriteKit
import SwiftUI

/// The SpriteKit scene, owned by the controller so a SwiftUI refresh never recreates the table.
struct TableSceneView: View {
  let controller: TableController

  var body: some View {
    SpriteView(scene: controller.scene, preferredFramesPerSecond: 120)
      .accessibilityIdentifier("table.scene")
  }
}
