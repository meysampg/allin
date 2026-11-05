import SpriteKit
import SwiftUI

/// The mini table: a replay scene owned by the review controller.
struct ReviewTableView: View {
  let controller: ReviewController

  var body: some View {
    SpriteView(scene: controller.scene, preferredFramesPerSecond: 60)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("review.table")
  }
}
