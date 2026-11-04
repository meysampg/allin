import PokerCore
import SwiftUI
import ThemeKit

/// SwiftUI view of a resolved theme: palette colors and the display/body fonts.
public struct Theme: Sendable {
  public let resolver: ThemeResolver

  public init(resolver: ThemeResolver) {
    self.resolver = resolver
  }

  /// The built-in code-drawn theme.
  public static let hearthwood = Theme(resolver: .codeDrawn)

  public func color(_ key: PaletteKey) -> Color {
    Color(resolver.palette[key])
  }

  public var ink: Color { color(.ink) }
  public var parchment: Color { color(.parchment) }
  public var gold: Color { color(.gold) }
  public var rune: Color { color(.rune) }
  public var felt: Color { color(.felt) }
  public var panel: Color { color(.panel) }
  public var good: Color { color(.good) }
  public var bad: Color { color(.bad) }
  public var mute: Color { color(.mute) }
  public var night: Color { color(.night) }

  /// Suit color. Two-color mode: red for hearts and diamonds, black for the rest. Four-color mode adds blue
  /// diamonds and green clubs.
  public func suitColor(_ suit: Suit, fourColor: Bool) -> Color {
    switch suit {
    case .hearts: return color(.suitRed)
    case .spades: return color(.suitBlack)
    case .diamonds: return color(fourColor ? .suitBlue : .suitRed)
    case .clubs: return color(fourColor ? .suitGreen : .suitBlack)
    }
  }

  public func displayFont(size: CGFloat) -> Font {
    font(for: .fontDisplay, size: size, defaultWeight: .heavy, defaultDesign: .serif)
  }

  public func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    font(for: .fontBody, size: size, weight: weight, defaultWeight: .regular, defaultDesign: .rounded)
  }

  private func font(
    for slot: AssetSlot, size: CGFloat, weight: Font.Weight? = nil, defaultWeight: Font.Weight,
    defaultDesign: Font.Design
  ) -> Font {
    var design = defaultDesign
    var resolvedWeight = defaultWeight
    if case .procedural(_, let params) = resolver.resolve(slot) {
      design = Theme.design(params.string("design", default: ""), default: defaultDesign)
      resolvedWeight = Theme.weight(params.string("weight", default: ""), default: defaultWeight)
    }
    return .system(size: size, weight: weight ?? resolvedWeight, design: design)
  }

  private static func design(_ name: String, default d: Font.Design) -> Font.Design {
    switch name {
    case "serif": return .serif
    case "rounded": return .rounded
    case "monospaced": return .monospaced
    case "default": return .default
    default: return d
    }
  }

  private static func weight(_ name: String, default d: Font.Weight) -> Font.Weight {
    switch name {
    case "ultraLight": return .ultraLight
    case "thin": return .thin
    case "light": return .light
    case "regular": return .regular
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    case "heavy": return .heavy
    case "black": return .black
    default: return d
    }
  }
}
