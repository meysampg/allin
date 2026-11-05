import Curriculum
import SwiftUI

/// A code-drawn venue picture: village house, stone town hall, castle or mountain cave.
struct VenueSilhouette: View {
  let icon: VenueIcon
  @Environment(\.theme) private var theme

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(LinearGradient(colors: [theme.parchment, theme.gold.opacity(0.35)], startPoint: .top, endPoint: .bottom))
      shape
        .fill(theme.ink.opacity(0.88))
        .padding(8)
      detail
        .fill(theme.parchment.opacity(0.9))
        .padding(8)
    }
    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.ink.opacity(0.6), lineWidth: 1.5))
    .accessibilityHidden(true)
  }

  private var shape: AnyShape {
    switch icon {
    case .village: AnyShape(HouseShape())
    case .townHall: AnyShape(TownHallShape())
    case .castle: AnyShape(CastleShape())
    case .cave: AnyShape(CaveShape())
    }
  }

  /// Windows, doors and gates, cut out of the silhouette in parchment.
  private var detail: AnyShape {
    switch icon {
    case .village: AnyShape(HouseDetail())
    case .townHall: AnyShape(TownHallDetail())
    case .castle: AnyShape(CastleDetail())
    case .cave: AnyShape(CaveDetail())
    }
  }
}

private func pt(_ r: CGRect, _ x: Double, _ y: Double) -> CGPoint {
  CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
}

private func box(_ r: CGRect, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
  CGRect(x: r.minX + x * r.width, y: r.minY + y * r.height, width: w * r.width, height: h * r.height)
}

private struct HouseShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: pt(r, 0.12, 0.52))
    p.addLine(to: pt(r, 0.5, 0.12))
    p.addLine(to: pt(r, 0.88, 0.52))
    p.addLine(to: pt(r, 0.8, 0.52))
    p.addLine(to: pt(r, 0.8, 0.95))
    p.addLine(to: pt(r, 0.2, 0.95))
    p.addLine(to: pt(r, 0.2, 0.52))
    p.closeSubpath()
    p.addRect(box(r, 0.68, 0.12, 0.08, 0.2))
    return p
  }
}

private struct HouseDetail: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.addRoundedRect(in: box(r, 0.42, 0.62, 0.16, 0.33), cornerSize: CGSize(width: 4, height: 4))
    p.addRect(box(r, 0.27, 0.58, 0.1, 0.12))
    p.addRect(box(r, 0.63, 0.58, 0.1, 0.12))
    return p
  }
}

private struct TownHallShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: pt(r, 0.08, 0.4))
    p.addLine(to: pt(r, 0.5, 0.14))
    p.addLine(to: pt(r, 0.92, 0.4))
    p.closeSubpath()
    p.addRect(box(r, 0.12, 0.4, 0.76, 0.1))
    p.addRect(box(r, 0.12, 0.5, 0.76, 0.45))
    p.addRect(box(r, 0.46, 0.0, 0.08, 0.16))
    return p
  }
}

private struct TownHallDetail: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    for i in 0..<4 { p.addRect(box(r, 0.18 + Double(i) * 0.15, 0.56, 0.07, 0.3)) }
    p.addRoundedRect(in: box(r, 0.44, 0.62, 0.12, 0.33), cornerSize: CGSize(width: 5, height: 5))
    p.addEllipse(in: box(r, 0.44, 0.22, 0.12, 0.14))
    return p
  }
}

private struct CastleShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    // Curtain wall with a keep in the middle and a tower at each end.
    p.addRect(box(r, 0.1, 0.5, 0.8, 0.45))
    for tower in [0.06, 0.78] {
      p.addRect(box(r, tower, 0.28, 0.16, 0.67))
      for k in 0..<3 { p.addRect(box(r, tower + Double(k) * 0.06, 0.2, 0.04, 0.1)) }
    }
    p.addRect(box(r, 0.36, 0.2, 0.28, 0.4))
    for k in 0..<4 { p.addRect(box(r, 0.36 + Double(k) * 0.08, 0.12, 0.05, 0.1)) }
    p.move(to: pt(r, 0.5, 0.0))
    p.addLine(to: pt(r, 0.5, 0.12))
    p.addLine(to: pt(r, 0.6, 0.06))
    p.closeSubpath()
    return p
  }
}

private struct CastleDetail: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.addRoundedRect(in: box(r, 0.44, 0.68, 0.12, 0.27), cornerSize: CGSize(width: 6, height: 6))
    p.addRect(box(r, 0.12, 0.42, 0.04, 0.12))
    p.addRect(box(r, 0.84, 0.42, 0.04, 0.12))
    p.addRect(box(r, 0.47, 0.3, 0.06, 0.14))
    return p
  }
}

private struct CaveShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: pt(r, 0.02, 0.95))
    p.addLine(to: pt(r, 0.3, 0.38))
    p.addLine(to: pt(r, 0.42, 0.52))
    p.addLine(to: pt(r, 0.62, 0.1))
    p.addLine(to: pt(r, 0.98, 0.95))
    p.closeSubpath()
    return p
  }
}

private struct CaveDetail: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: pt(r, 0.42, 0.95))
    p.addLine(to: pt(r, 0.42, 0.72))
    p.addQuadCurve(to: pt(r, 0.7, 0.72), control: pt(r, 0.56, 0.38))
    p.addLine(to: pt(r, 0.7, 0.95))
    p.closeSubpath()
    p.addEllipse(in: box(r, 0.5, 0.78, 0.1, 0.1))
    return p
  }
}
