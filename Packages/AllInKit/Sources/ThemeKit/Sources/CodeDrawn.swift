import Foundation

/// The built-in, always-available source for every slot.
public enum CodeDrawn {
  public static let knownCharacterIDs: [String] = [
    "you", "grumli", "zib", "vexa", "mott", "oryn", "bram", "patron", "morwen", "ysolde", "hoot", "random",
  ]

  public static func `default`(_ slot: AssetSlot) -> AssetSource {
    switch slot {
    case .cardFace, .cardFaceOverride, .cardCourt:
      .procedural(.cardHearthwood, ["frame": "gilded"])
    case .cardBack:
      .procedural(.backRuneknot, ["hue": 0.08])
    case .cardBackReward(let id):
      .procedural(.backRuneknot, ["hue": .number(stableHue(id))])
    case .tableFelt:
      .procedural(.feltCloth, ["color": "#1F4D3A"])
    case .tableRail:
      .procedural(.railOak, [:])
    case .tableRunes:
      .procedural(.runesRing, ["glyphs": "elder", "pulse": 0.6, "color": "#7FE3FF"])
    case .tableLight:
      .procedural(.lightCandle, ["warmth": 0.7])
    case .tableDealerButton:
      .procedural(.buttonDealer, [:])
    case .tableShoe:
      .procedural(.shoeDragon, [:])
    case .chip(let d):
      .procedural(chipID(d), [:])
    case .avatar(let id):
      .procedural(
        .medallionSigil,
        [
          "symbol": .string(avatarStyle(id).symbol), "ring": .string(avatarStyle(id).ring),
          "initial": .string(String(id.prefix(1)).uppercased()),
        ])
    case .characterFull(let id):
      .procedural(.characterSilhouette, ["symbol": .string(avatarStyle(id).symbol)])
    case .venueMap(let id):
      .procedural(.venueSilhouette, ["icon": .string(id)])
    case .venueBanner:
      .procedural(.venueBanner, [:])
    case .venueBackground:
      .procedural(.venueBackdrop, [:])
    case .venueStamp:
      .procedural(.venueStamp, [:])
    case .sound(let e):
      soundSource(e)
    case .music:
      .procedural(.musicSilence, [:])
    case .uiButtonFrame:
      .procedural(.buttonFrame, [:])
    case .uiPanelParchment:
      .procedural(.panelParchment, [:])
    case .fontDisplay:
      .procedural(.fontSystem, ["design": "serif", "weight": "heavy"])
    case .fontBody:
      .procedural(.fontSystem, ["design": "rounded", "weight": "regular"])
    case .fx(let k):
      .procedural(.fxParticles, ["preset": .string(k.rawValue)])
    }
  }

  private static func chipID(_ d: ChipDenomination) -> ProceduralID {
    switch d {
    case .one: .coinCopper
    case .five: .coinSilver
    case .twentyFive: .coinGold
    case .hundred: .gemRuby
    case .fiveHundred: .gemSapphire
    case .thousand: .gemEmerald
    case .fiveThousand: .gemDiamond
    case .twentyFiveThousand: .gemDragonstone
    }
  }

  private static func soundSource(_ e: SoundEvent) -> AssetSource {
    switch e {
    case .cardDeal: .procedural(.sfxFlick, ["pitch": 1])
    case .cardFlip: .procedural(.sfxFlick, ["pitch": 1.4, "length": 0.05])
    case .chipBet: .procedural(.sfxClink, ["count": 1])
    case .chipStack: .procedural(.sfxClink, ["count": 3])
    case .potSweep: .procedural(.sfxSweep, [:])
    case .win: .procedural(.sfxBell, ["notes": 3])
    case .allIn: .procedural(.sfxBell, ["notes": 1, "base": 220])
    case .timer: .procedural(.sfxTick, [:])
    case .uiTap: .procedural(.sfxTick, ["gain": 0.4])
    case .uiSuccess: .procedural(.sfxBell, ["notes": 2, "base": 660])
    case .uiFail: .procedural(.sfxTone, ["from": 440, "to": 220])
    case .stamp: .procedural(.sfxThump, [:])
    }
  }

  private static func avatarStyle(_ id: String) -> (symbol: String, ring: String) {
    switch id {
    case "you": ("star.fill", "#D9A441")
    case "grumli": ("hammer.fill", "#B5651D")
    case "zib": ("gearshape.fill", "#6B8E23")
    case "vexa": ("leaf.fill", "#4F7CAC")
    case "mott": ("book.closed.fill", "#8B6F47")
    case "oryn": ("wand.and.stars", "#6A4C93")
    case "bram": ("shield.fill", "#7A7A7A")
    case "patron": ("person.fill", "#9C8B6E")
    case "morwen": ("moon.stars.fill", "#5B5B8F")
    case "ysolde": ("flame.fill", "#A23B2A")
    case "hoot": ("bird.fill", "#8A6D3B")
    default: ("questionmark", "#777777")
    }
  }

  /// A hue in 0...1 derived from the id with FNV-1a, so it is stable across runs.
  private static func stableHue(_ id: String) -> Double {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in id.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    return Double(hash % 1000) / 1000
  }
}
