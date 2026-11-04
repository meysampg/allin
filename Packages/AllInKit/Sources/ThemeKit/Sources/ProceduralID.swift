import Foundation

/// The name of a code-drawn generator, such as "coin.gold".
public struct ProceduralID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// nil when the id is unknown.
  public var kind: AssetKind? { ProceduralID.known[self] }

  public static let cardHearthwood: ProceduralID = "card.hearthwood"
  public static let backRuneknot: ProceduralID = "back.runeknot"
  public static let feltCloth: ProceduralID = "felt.cloth"
  public static let railOak: ProceduralID = "rail.oak"
  public static let runesRing: ProceduralID = "runes.ring"
  public static let lightCandle: ProceduralID = "light.candle"
  public static let buttonDealer: ProceduralID = "button.dealer"
  public static let shoeDragon: ProceduralID = "shoe.dragon"
  public static let coinCopper: ProceduralID = "coin.copper"
  public static let coinSilver: ProceduralID = "coin.silver"
  public static let coinGold: ProceduralID = "coin.gold"
  public static let gemRuby: ProceduralID = "gem.ruby"
  public static let gemSapphire: ProceduralID = "gem.sapphire"
  public static let gemEmerald: ProceduralID = "gem.emerald"
  public static let gemDiamond: ProceduralID = "gem.diamond"
  public static let gemDragonstone: ProceduralID = "gem.dragonstone"
  public static let medallionSigil: ProceduralID = "medallion.sigil"
  public static let characterSilhouette: ProceduralID = "character.silhouette"
  public static let venueSilhouette: ProceduralID = "venue.silhouette"
  public static let venueBanner: ProceduralID = "venue.banner"
  public static let venueBackdrop: ProceduralID = "venue.backdrop"
  public static let venueStamp: ProceduralID = "venue.stamp"
  public static let panelParchment: ProceduralID = "panel.parchment"
  public static let buttonFrame: ProceduralID = "button.frame"
  public static let sfxFlick: ProceduralID = "sfx.flick"
  public static let sfxClink: ProceduralID = "sfx.clink"
  public static let sfxSweep: ProceduralID = "sfx.sweep"
  public static let sfxBell: ProceduralID = "sfx.bell"
  public static let sfxTick: ProceduralID = "sfx.tick"
  public static let sfxThump: ProceduralID = "sfx.thump"
  public static let sfxTone: ProceduralID = "sfx.tone"
  public static let musicSilence: ProceduralID = "music.silence"
  public static let fontSystem: ProceduralID = "font.system"
  public static let fxParticles: ProceduralID = "fx.particles"

  public static let known: [ProceduralID: AssetKind] = [
    .cardHearthwood: .image, .backRuneknot: .image, .feltCloth: .image, .railOak: .image, .runesRing: .image,
    .lightCandle: .image, .buttonDealer: .image, .shoeDragon: .image,
    .coinCopper: .image, .coinSilver: .image, .coinGold: .image,
    .gemRuby: .image, .gemSapphire: .image, .gemEmerald: .image, .gemDiamond: .image, .gemDragonstone: .image,
    .medallionSigil: .image, .characterSilhouette: .image, .venueSilhouette: .image, .venueBanner: .image,
    .venueBackdrop: .image, .venueStamp: .image, .panelParchment: .image, .buttonFrame: .image,
    .sfxFlick: .sound, .sfxClink: .sound, .sfxSweep: .sound, .sfxBell: .sound, .sfxTick: .sound,
    .sfxThump: .sound, .sfxTone: .sound,
    .musicSilence: .music, .fontSystem: .font, .fxParticles: .effect,
  ]
}
