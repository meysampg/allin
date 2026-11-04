import Foundation
import PokerAI
import PokerCore
import PokerHost

/// Shared fixtures of the sim gates. Fixed base seeds keep every gate deterministic.
enum SimSupport {
  static let randomSeed: UInt64 = 0x51A1
  static let orynSeed: UInt64 = 0x51A2
  static let styleSeed: UInt64 = 0x51A3
  static let distributionSeed: UInt64 = 0x51A4
  static let sessionSeed: UInt64 = 0x51A5

  static let shards = 4
  static let gateIDs = BotRoster.gateIDs
  static let allIDs = BotRoster.gateIDs + ["oryn"]

  static func bot(_ id: String) -> RosterBot {
    try! BotRoster.bot(id)
  }

  static func contestant(_ id: String) -> Contestant {
    let bot = bot(id)
    return Contestant(name: bot.name, strategy: bot.strategy)
  }

  static let random = Contestant(name: "Random", strategy: UniformRandomStrategy())

  static func bbPer100Row(_ label: String, _ win: WinRate, hands: Int, seconds: Double) -> String {
    let rate = String(format: "%7.1f", win.bbPer100)
    let low = String(format: "%7.1f", win.ciLow)
    let high = String(format: "%7.1f", win.ciHigh)
    let speed = String(format: "%.0f", Double(hands) / max(seconds, 0.001))
    return "SIM \(label): \(rate) bb/100  CI [\(low), \(high)]  \(hands) hands, \(speed) hands/s"
  }

  static func timed<T>(_ body: () async -> T) async -> (value: T, seconds: Double) {
    let start = Date()
    let value = await body()
    return (value, Date().timeIntervalSince(start))
  }
}
