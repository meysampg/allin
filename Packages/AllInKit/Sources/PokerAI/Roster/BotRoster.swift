import Foundation
import PokerCore

/// One playable bot of the roster.
public struct RosterBot: Sendable {
  public let id: String
  public let name: String
  public let strategy: any StrategyProvider

  public init(id: String, name: String, strategy: any StrategyProvider) {
    self.id = id
    self.name = name
    self.strategy = strategy
  }
}

/// The characters of `Content/characters` as ready-to-play strategies.
public enum BotRoster {
  /// The personalities every gate is run against (Oryn is the benchmark, not a subject).
  public static let gateIDs: [String] = ["grumli", "zib", "vexa", "mott", "bram", "patron"]

  /// Every character in `directory`, sorted by id.
  public static func load(
    directory: URL = BotCharacter.sourceTreeDirectory, patronSeed: UInt64 = 1
  ) throws -> [RosterBot] {
    try BotCharacter.loadAll(directory: directory).map { make($0, patronSeed: patronSeed) }
  }

  /// A single character by id.
  public static func bot(
    _ id: String, directory: URL = BotCharacter.sourceTreeDirectory, patronSeed: UInt64 = 1
  ) throws -> RosterBot {
    let file = directory.appendingPathComponent("\(id).json")
    return make(try BotCharacter.load(from: file), patronSeed: patronSeed)
  }

  private static func make(_ character: BotCharacter, patronSeed: UInt64) -> RosterBot {
    let strategy: any StrategyProvider
    switch character.strategy {
    case .personality:
      var params = character.params!
      if character.id == "patron", let variation = character.variation {
        params = params.varied(by: variation, seed: patronSeed)
      }
      strategy = PersonalityStrategy(params: params, seed: stableHash(character.id))
    case .baseline:
      strategy = BaselineStrategy()
    }
    return RosterBot(id: character.id, name: character.name, strategy: strategy)
  }

  /// FNV-1a over the UTF-8 bytes: stable across processes (unlike `hashValue`).
  private static func stableHash(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
  }
}
