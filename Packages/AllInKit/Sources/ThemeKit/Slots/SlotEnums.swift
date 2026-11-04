import Foundation

public enum ChipDenomination: Int, CaseIterable, Sendable, Comparable, Codable {
  case one = 1
  case five = 5
  case twentyFive = 25
  case hundred = 100
  case fiveHundred = 500
  case thousand = 1000
  case fiveThousand = 5000
  case twentyFiveThousand = 25000

  public static func < (lhs: ChipDenomination, rhs: ChipDenomination) -> Bool { lhs.rawValue < rhs.rawValue }

  /// "1", "5", "25", "100", "500", "1k", "5k", "25k".
  public var slotKey: String {
    rawValue >= 1000 ? "\(rawValue / 1000)k" : "\(rawValue)"
  }
}

public enum SoundEvent: String, CaseIterable, Sendable, Codable {
  case cardDeal = "card.deal"
  case cardFlip = "card.flip"
  case chipBet = "chip.bet"
  case chipStack = "chip.stack"
  case potSweep = "pot.sweep"
  case win
  case allIn = "allin"
  case timer
  case uiTap = "ui.tap"
  case uiSuccess = "ui.success"
  case uiFail = "ui.fail"
  case stamp
}

public enum EffectKind: String, CaseIterable, Sendable, Codable { case coinBurst, magicSparks, embers, confetti }

public enum AssetKind: String, Sendable { case image, sound, music, font, effect }
