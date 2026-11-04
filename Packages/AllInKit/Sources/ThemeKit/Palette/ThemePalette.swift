import Foundation

public enum PaletteKey: String, CaseIterable, Sendable, Codable {
  case ink, parchment, gold, rune, suitRed, suitBlack, suitBlue, suitGreen, cardFace, felt, rail, panel, good, bad,
    mute, night
}

public struct ThemePalette: Sendable, Hashable {
  private let explicit: [PaletteKey: ThemeColor]
  private let resolved: [PaletteKey: ThemeColor]

  public static let hearthwood = ThemePalette(
    explicit: [:],
    base: [
      .ink: "#2A1E14", .parchment: "#F3E6C8", .gold: "#D9A441", .rune: "#7FE3FF",
      .suitRed: "#B3261E", .suitBlack: "#1B1B1B", .suitBlue: "#1F5FBF", .suitGreen: "#1E7A3C",
      .cardFace: "#FBF6EA", .felt: "#1F4D3A", .rail: "#6B4423", .panel: "#E9D9B4",
      .good: "#2E8B57", .bad: "#C0392B", .mute: "#8A7F6A", .night: "#14100C",
    ].compactMapValues { ThemeColor(hex: $0) })

  private init(explicit: [PaletteKey: ThemeColor], base: [PaletteKey: ThemeColor]) {
    self.explicit = explicit
    self.resolved = base.merging(explicit) { _, new in new }
  }

  /// Missing keys are filled from `.hearthwood`.
  public init(colors: [PaletteKey: ThemeColor]) {
    self.init(explicit: colors, base: ThemePalette.hearthwoodColors)
  }

  private static var hearthwoodColors: [PaletteKey: ThemeColor] { hearthwood.resolved }

  public static func == (lhs: ThemePalette, rhs: ThemePalette) -> Bool { lhs.resolved == rhs.resolved }

  public func hash(into hasher: inout Hasher) { hasher.combine(resolved) }

  public subscript(_ key: PaletteKey) -> ThemeColor { resolved[key] ?? ThemeColor(red: 0, green: 0, blue: 0) }

  /// This palette's explicitly set keys win; every other key comes from `base`.
  public func merged(over base: ThemePalette) -> ThemePalette {
    ThemePalette(explicit: base.explicit.merging(explicit) { _, new in new }, base: base.resolved)
  }
}
