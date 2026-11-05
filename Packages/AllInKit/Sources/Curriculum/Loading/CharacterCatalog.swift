import Foundation
import PokerAI
import PokerCore

/// The bot characters of `Content/characters`: playable strategies plus presentational info.
public struct CharacterCatalog: Sendable {
  public let characters: [String: BotCharacter]
  public let info: [String: CharacterInfo]
  private let strategies: [String: any StrategyProvider]

  public init(
    characters: [String: BotCharacter], info: [String: CharacterInfo],
    strategies: [String: any StrategyProvider]
  ) {
    self.characters = characters
    self.info = info
    self.strategies = strategies
  }

  /// `BotCharacter.loadAll` and `BotRoster.load` (strategies cached), plus lenient `CharacterInfo` of every file.
  public static func load(directory: URL, patronSeed: UInt64 = 1) throws -> CharacterCatalog {
    let loaded = try BotCharacter.loadAll(directory: directory)
    let roster = try BotRoster.load(directory: directory, patronSeed: patronSeed)
    var info: [String: CharacterInfo] = [:]
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for file in files {
      let parsed = try JSONDecoder().decode(CharacterInfo.self, from: Data(contentsOf: file))
      info[parsed.id] = parsed
    }
    return CharacterCatalog(
      characters: Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }), info: info,
      strategies: Dictionary(roster.map { ($0.id, $0.strategy) }, uniquingKeysWith: { first, _ in first }))
  }

  public func contains(_ id: String) -> Bool { characters[id] != nil }

  public func strategy(_ id: String) -> (any StrategyProvider)? { strategies[id] }

  /// Info name, else the character name, else the id.
  public func name(_ id: String) -> String {
    if let name = info[id]?.name, !name.isEmpty { return name }
    return characters[id]?.name ?? id
  }

  public func style(_ id: String) -> String? {
    if let style = info[id]?.style, !style.isEmpty { return style }
    return characters[id]?.style
  }

  /// Names the character may be shown under: `info.names`, else its name.
  public func names(_ id: String) -> [String] {
    if let names = info[id]?.names, !names.isEmpty { return names }
    return [name(id)]
  }
}
