import SwiftUI

/// The venue anchors of the career map, normalized from the wireframe (1120 × 672).
enum RealmLayout {
  static let designSize = CGSize(width: 1120, height: 672)
  static let anchors: [CGPoint] = [
    CGPoint(x: 150, y: 420), CGPoint(x: 470, y: 380), CGPoint(x: 780, y: 330), CGPoint(x: 990, y: 230),
  ]

  /// Anchor `index` (clamped) scaled into `size`.
  static func point(_ index: Int, in size: CGSize) -> CGPoint {
    let a = anchors[min(max(index, 0), anchors.count - 1)]
    return CGPoint(x: a.x / designSize.width * size.width, y: a.y / designSize.height * size.height)
  }
}

/// The dashed road through the four venue anchors, rising from left to right.
struct RealmPath: Shape {
  func path(in rect: CGRect) -> Path {
    func p(_ x: Double, _ y: Double) -> CGPoint {
      CGPoint(
        x: rect.minX + x / RealmLayout.designSize.width * rect.width,
        y: rect.minY + y / RealmLayout.designSize.height * rect.height)
    }
    var path = Path()
    path.move(to: p(150, 420))
    path.addCurve(to: p(470, 380), control1: p(300, 300), control2: p(380, 520))
    path.addCurve(to: p(780, 330), control1: p(560, 240), control2: p(700, 250))
    path.addCurve(to: p(990, 230), control1: p(860, 410), control2: p(950, 200))
    return path
  }
}
