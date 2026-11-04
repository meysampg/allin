import Foundation

public enum StrategyKind: String, Codable, Sendable { case personality, baseline }

/// Why a character file could not be loaded.
public enum BotCharacterError: Error, Sendable, Equatable {
  case unsupportedSchema(id: String, version: Int)
  case missingParams(id: String)
  case invalidParams(id: String, reason: String)
  case unknownVariationKey(id: String, key: String)
  case emptyField(String)
}

/// A character file of `Content/characters`.
public struct BotCharacter: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let id: String
  public let name: String
  public let style: String
  public let strategy: StrategyKind
  /// Required when `strategy == .personality`.
  public let params: PersonalityParams?
  /// Keys must be `PersonalityParams` field names.
  public let variation: [String: Double]?

  public init(
    schemaVersion: Int = 1, id: String, name: String, style: String, strategy: StrategyKind,
    params: PersonalityParams? = nil, variation: [String: Double]? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.style = style
    self.strategy = strategy
    self.params = params
    self.variation = variation
  }

  /// Checks the schema version, the parameters and the variation keys.
  public func validate() throws {
    guard schemaVersion == 1 else { throw BotCharacterError.unsupportedSchema(id: id, version: schemaVersion) }
    guard !id.isEmpty else { throw BotCharacterError.emptyField("id") }
    guard !name.isEmpty else { throw BotCharacterError.emptyField("name") }
    if strategy == .personality {
      guard let params else { throw BotCharacterError.missingParams(id: id) }
      do { try params.validate() } catch {
        throw BotCharacterError.invalidParams(id: id, reason: "\(error)")
      }
    }
    for key in (variation ?? [:]).keys where !PersonalityParams.variableFieldNames.contains(key) {
      throw BotCharacterError.unknownVariationKey(id: id, key: key)
    }
  }

  public static func load(from url: URL) throws -> BotCharacter {
    let character = try JSONDecoder().decode(BotCharacter.self, from: Data(contentsOf: url))
    try character.validate()
    return character
  }

  /// Every `*.json` file of `directory`, validated, sorted by id.
  public static func loadAll(directory: URL) throws -> [BotCharacter] {
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
    return try files.map { try load(from: $0) }.sorted { $0.id < $1.id }
  }

  /// `<repo>/Content/characters`, found from this file's `#filePath` (dev tools and tests only).
  public static var sourceTreeDirectory: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return url.appending(path: "Content/characters")
  }
}
