import CoreGraphics
import Foundation
import ThemeKit

/// Draws chips top-down: coins for small denominations, faceted gems in a gold bezel for large ones.
public struct ChipRenderer: Sendable {
  private let resolver: ThemeResolver

  public init(resolver: ThemeResolver) { self.resolver = resolver }

  public func chipImage(_ denomination: ChipDenomination, pixelDiameter: Int) -> CGImage {
    let d = max(pixelDiameter, 8)
    let slot = AssetSlot.chip(denomination)
    if case .file(let url) = resolver.resolve(slot), let image = ThemeImageIO.loadImage(at: url) {
      let context = ThemeImageIO.makeContext(pixelWidth: d, pixelHeight: d)
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: d, height: d))
      return context.makeImage()!
    }
    var params = ProceduralParams()
    var procedural = Self.defaultStyle(for: denomination)
    if case .procedural(let id, let p) = resolver.resolve(slot) {
      params = p
      procedural = Style(rawValue: id.rawValue) ?? procedural
    }
    let context = ThemeImageIO.makeContext(pixelWidth: d, pixelHeight: d)
    let palette = resolver.palette
    let color = params.color("color", default: procedural.color)
    if procedural.isGem {
      Self.drawGem(in: context, size: CGFloat(d), color: color, gold: palette[.gold], ember: procedural == .dragonstone)
    } else {
      Self.drawCoin(in: context, size: CGFloat(d), color: color, label: denomination.slotKey, ink: palette[.ink])
    }
    return context.makeImage()!
  }

  // MARK: Styles

  enum Style: String {
    case copper = "coin.copper"
    case silver = "coin.silver"
    case gold = "coin.gold"
    case ruby = "gem.ruby"
    case sapphire = "gem.sapphire"
    case emerald = "gem.emerald"
    case diamond = "gem.diamond"
    case dragonstone = "gem.dragonstone"

    var isGem: Bool { rawValue.hasPrefix("gem.") }
    var color: ThemeColor {
      switch self {
      case .copper: return ThemeColor(hex: "#B87333")!
      case .silver: return ThemeColor(hex: "#C0C0C0")!
      case .gold: return ThemeColor(hex: "#D4AF37")!
      case .ruby: return ThemeColor(hex: "#9B111E")!
      case .sapphire: return ThemeColor(hex: "#0F52BA")!
      case .emerald: return ThemeColor(hex: "#50C878")!
      case .diamond: return ThemeColor(hex: "#B9F2FF")!
      case .dragonstone: return ThemeColor(hex: "#3B0A45")!
      }
    }
  }

  static func defaultStyle(for denomination: ChipDenomination) -> Style {
    switch denomination {
    case .one: return .copper
    case .five: return .silver
    case .twentyFive: return .gold
    case .hundred: return .ruby
    case .fiveHundred: return .sapphire
    case .thousand: return .emerald
    case .fiveThousand: return .diamond
    case .twentyFiveThousand: return .dragonstone
    }
  }

  // MARK: Drawing

  private static func drawCoin(
    in context: CGContext, size: CGFloat, color: ThemeColor, label: String, ink: ThemeColor
  ) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.03, dy: size * 0.03)
    context.setFillColor(TableRenderer.shade(color, 0.45).cgColor)
    context.fillEllipse(in: rect)
    // Rim with embossed notches.
    let rim = rect.insetBy(dx: size * 0.025, dy: size * 0.025)
    context.setFillColor(TableRenderer.shade(color, 1.15).cgColor)
    context.fillEllipse(in: rim)
    context.setStrokeColor(TableRenderer.shade(color, 0.7).cgColor)
    context.setLineWidth(max(size * 0.035, 1))
    let notches = 24
    let centre = CGPoint(x: size / 2, y: size / 2)
    for i in 0..<notches {
      let angle = Double(i) / Double(notches) * 2 * .pi
      let r1 = rim.width / 2 * 0.86
      let r2 = rim.width / 2 * 0.98
      context.move(to: CGPoint(x: centre.x + CGFloat(cos(angle)) * r1, y: centre.y + CGFloat(sin(angle)) * r1))
      context.addLine(to: CGPoint(x: centre.x + CGFloat(cos(angle)) * r2, y: centre.y + CGFloat(sin(angle)) * r2))
    }
    context.strokePath()
    // Face, inner ring and highlight.
    let face = rim.insetBy(dx: size * 0.09, dy: size * 0.09)
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: face)
    context.setStrokeColor(TableRenderer.shade(color, 0.6).cgColor)
    context.setLineWidth(max(size * 0.03, 1))
    context.strokeEllipse(in: face.insetBy(dx: size * 0.05, dy: size * 0.05))
    context.setStrokeColor(TableRenderer.shade(color, 1.4).cgColor)
    context.setLineWidth(max(size * 0.015, 1))
    context.strokeEllipse(in: face.insetBy(dx: size * 0.012, dy: size * 0.012))
    TextDrawing.drawCentered(
      label, in: context, center: centre, fontSize: size * (label.count > 2 ? 0.2 : 0.28),
      color: TableRenderer.shade(color, 0.4))
    _ = ink
  }

  private static func drawGem(in context: CGContext, size: CGFloat, color: ThemeColor, gold: ThemeColor, ember: Bool) {
    let centre = CGPoint(x: size / 2, y: size / 2)
    let bezel = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.03, dy: size * 0.03)
    context.setFillColor(TableRenderer.shade(gold, 0.6).cgColor)
    context.fillEllipse(in: bezel)
    context.setFillColor(gold.cgColor)
    context.fillEllipse(in: bezel.insetBy(dx: size * 0.03, dy: size * 0.03))
    context.setFillColor(TableRenderer.shade(gold, 0.55).cgColor)
    context.fillEllipse(in: bezel.insetBy(dx: size * 0.1, dy: size * 0.1))
    if ember {
      context.setStrokeColor(ThemeColor(hex: "#FF6A1F")!.cgColor)
      context.setLineWidth(max(size * 0.03, 1))
      context.strokeEllipse(in: bezel.insetBy(dx: size * 0.12, dy: size * 0.12))
    }
    // Octagon with facets.
    let outerR = size * 0.34
    let innerR = size * 0.16
    func vertex(_ i: Int, _ r: CGFloat) -> CGPoint {
      let angle = (Double(i) + 0.5) / 8 * 2 * .pi
      return CGPoint(x: centre.x + CGFloat(cos(angle)) * r, y: centre.y + CGFloat(sin(angle)) * r)
    }
    let octagon = CGMutablePath()
    for i in 0..<8 { i == 0 ? octagon.move(to: vertex(i, outerR)) : octagon.addLine(to: vertex(i, outerR)) }
    octagon.closeSubpath()
    context.addPath(octagon)
    context.setFillColor(color.cgColor)
    context.fillPath()
    for i in 0..<8 {
      let next = (i + 1) % 8
      let facet = CGMutablePath()
      facet.move(to: vertex(i, outerR))
      facet.addLine(to: vertex(next, outerR))
      facet.addLine(to: vertex(next, innerR))
      facet.addLine(to: vertex(i, innerR))
      facet.closeSubpath()
      // Facets facing up-left are lighter, down-right darker.
      let lightness = 1.0 + 0.35 * cos((Double(i) + 1) / 8 * 2 * .pi - .pi * 0.75)
      context.addPath(facet)
      context.setFillColor(TableRenderer.shade(color, lightness).cgColor)
      context.fillPath()
    }
    let table = CGMutablePath()
    for i in 0..<8 { i == 0 ? table.move(to: vertex(i, innerR)) : table.addLine(to: vertex(i, innerR)) }
    table.closeSubpath()
    context.addPath(table)
    context.setFillColor(TableRenderer.shade(color, 1.25).cgColor)
    context.fillPath()
    context.setStrokeColor(TableRenderer.shade(color, 0.5).cgColor)
    context.setLineWidth(max(size * 0.012, 1))
    context.addPath(octagon)
    context.strokePath()
    for i in 0..<8 {
      context.move(to: vertex(i, outerR))
      context.addLine(to: vertex(i, innerR))
    }
    context.strokePath()
  }
}
