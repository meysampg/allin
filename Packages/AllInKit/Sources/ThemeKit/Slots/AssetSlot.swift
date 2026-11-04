import Foundation

public enum AssetSlot: Sendable, Hashable, CustomStringConvertible {
  case cardFace
  case cardFaceOverride(CardKey)
  /// Rank 9, 10 or 11 only (jack, queen, king).
  case cardCourt(CardKey)
  case cardBack
  case cardBackReward(String)
  case tableFelt, tableRail, tableRunes, tableLight, tableDealerButton, tableShoe
  case chip(ChipDenomination)
  case avatar(String)
  case characterFull(String)
  case venueMap(String), venueBanner(String), venueBackground(String), venueStamp(String)
  case sound(SoundEvent)
  case music(String)
  case uiButtonFrame, uiPanelParchment, fontDisplay, fontBody
  case fx(EffectKind)

  public var id: String {
    switch self {
    case .cardFace: "card.face"
    case .cardFaceOverride(let c): "card.face.\(c.symbol)"
    case .cardCourt(let c): "card.court.\(c.symbol)"
    case .cardBack: "card.back"
    case .cardBackReward(let r): "card.back.\(r)"
    case .tableFelt: "table.felt"
    case .tableRail: "table.rail"
    case .tableRunes: "table.runes"
    case .tableLight: "table.light"
    case .tableDealerButton: "table.dealerButton"
    case .tableShoe: "table.shoe"
    case .chip(let d): "chip.\(d.slotKey)"
    case .avatar(let i): "avatar.\(i)"
    case .characterFull(let i): "character.\(i).full"
    case .venueMap(let i): "venue.\(i).map"
    case .venueBanner(let i): "venue.\(i).banner"
    case .venueBackground(let i): "venue.\(i).background"
    case .venueStamp(let i): "venue.\(i).stamp"
    case .sound(let e): "sound.\(e.rawValue)"
    case .music(let v): "music.\(v)"
    case .uiButtonFrame: "ui.button.frame"
    case .uiPanelParchment: "ui.panel.parchment"
    case .fontDisplay: "font.display"
    case .fontBody: "font.body"
    case .fx(let k): "fx.\(k.rawValue)"
    }
  }

  public var description: String { id }

  public var kind: AssetKind {
    switch self {
    case .cardFace, .cardFaceOverride, .cardCourt, .cardBack, .cardBackReward,
      .tableFelt, .tableRail, .tableRunes, .tableLight, .tableDealerButton, .tableShoe,
      .chip, .avatar, .characterFull, .venueMap, .venueBanner, .venueBackground, .venueStamp,
      .uiButtonFrame, .uiPanelParchment:
      .image
    case .sound: .sound
    case .music: .music
    case .fontDisplay, .fontBody: .font
    case .fx: .effect
    }
  }

  public var fallbackSlot: AssetSlot? {
    switch self {
    case .cardFaceOverride, .cardCourt: .cardFace
    case .cardBackReward: .cardBack
    default: nil
    }
  }

  /// Lowercase `[a-z0-9_-]+`.
  static func isValidName(_ text: String) -> Bool {
    !text.isEmpty
      && text.unicodeScalars.allSatisfy {
        ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-"
      }
  }

  public init?(id: String) {
    let parts = id.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard let head = parts.first, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
    switch (head, parts.count) {
    case ("card", 2):
      switch parts[1] {
      case "face": self = .cardFace
      case "back": self = .cardBack
      default: return nil
      }
    case ("card", 3):
      switch parts[1] {
      case "face":
        guard let c = CardKey(symbol: parts[2]) else { return nil }
        self = .cardFaceOverride(c)
      case "court":
        guard let c = CardKey(symbol: parts[2]), (9...11).contains(c.rank) else { return nil }
        self = .cardCourt(c)
      case "back":
        guard AssetSlot.isValidName(parts[2]) else { return nil }
        self = .cardBackReward(parts[2])
      default: return nil
      }
    case ("table", 2):
      switch parts[1] {
      case "felt": self = .tableFelt
      case "rail": self = .tableRail
      case "runes": self = .tableRunes
      case "light": self = .tableLight
      case "dealerButton": self = .tableDealerButton
      case "shoe": self = .tableShoe
      default: return nil
      }
    case ("chip", 2):
      guard let d = ChipDenomination.allCases.first(where: { $0.slotKey == parts[1] }) else { return nil }
      self = .chip(d)
    case ("avatar", 2):
      guard AssetSlot.isValidName(parts[1]) else { return nil }
      self = .avatar(parts[1])
    case ("character", 3):
      guard parts[2] == "full", AssetSlot.isValidName(parts[1]) else { return nil }
      self = .characterFull(parts[1])
    case ("venue", 3):
      guard AssetSlot.isValidName(parts[1]) else { return nil }
      switch parts[2] {
      case "map": self = .venueMap(parts[1])
      case "banner": self = .venueBanner(parts[1])
      case "background": self = .venueBackground(parts[1])
      case "stamp": self = .venueStamp(parts[1])
      default: return nil
      }
    case ("sound", _) where parts.count >= 2:
      let name = parts.dropFirst().joined(separator: ".")
      guard let e = SoundEvent(rawValue: name) else { return nil }
      self = .sound(e)
    case ("music", 2):
      guard AssetSlot.isValidName(parts[1]) else { return nil }
      self = .music(parts[1])
    case ("ui", 3):
      switch (parts[1], parts[2]) {
      case ("button", "frame"): self = .uiButtonFrame
      case ("panel", "parchment"): self = .uiPanelParchment
      default: return nil
      }
    case ("font", 2):
      switch parts[1] {
      case "display": self = .fontDisplay
      case "body": self = .fontBody
      default: return nil
      }
    case ("fx", 2):
      guard let k = EffectKind(rawValue: parts[1]) else { return nil }
      self = .fx(k)
    default:
      return nil
    }
  }

  /// Every fixed case, 52 overrides, 12 courts, all chips, sounds and fx, plus per-id slots for the given ids.
  public static func catalog(
    characterIDs: [String] = CodeDrawn.knownCharacterIDs,
    venueIDs: [String] = ["tavern", "guild", "keep", "hoard"],
    rewardIDs: [String] = ["sample"]
  ) -> [AssetSlot] {
    var slots: [AssetSlot] = [
      .cardFace, .cardBack, .tableFelt, .tableRail, .tableRunes, .tableLight, .tableDealerButton, .tableShoe,
    ]
    slots += CardKey.all.map { .cardFaceOverride($0) }
    slots += CardKey.all.filter { (9...11).contains($0.rank) }.map { .cardCourt($0) }
    slots += rewardIDs.map { .cardBackReward($0) }
    slots += ChipDenomination.allCases.map { .chip($0) }
    for id in characterIDs { slots += [.avatar(id), .characterFull(id)] }
    for id in venueIDs {
      slots += [.venueMap(id), .venueBanner(id), .venueBackground(id), .venueStamp(id), .music(id)]
    }
    slots += SoundEvent.allCases.map { .sound($0) }
    slots += [.uiButtonFrame, .uiPanelParchment, .fontDisplay, .fontBody]
    slots += EffectKind.allCases.map { .fx($0) }
    return slots
  }
}
