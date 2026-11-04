import Foundation

/// The decoded `theme.json` of a pack. Palette and slot keys stay raw so the validator can report problems.
public struct ThemeManifest: Codable, Sendable, Hashable {
  public static let currentSchemaVersion = 1

  public struct SlotEntry: Codable, Sendable, Hashable {
    public var procedural: ProceduralID?
    public var params: ProceduralParams?
    public var file: String?
    public var files: [String]?

    public init(
      procedural: ProceduralID? = nil, params: ProceduralParams? = nil, file: String? = nil, files: [String]? = nil
    ) {
      self.procedural = procedural
      self.params = params
      self.file = file
      self.files = files
    }
  }

  public var schemaVersion: Int
  public var id: String
  public var name: String
  public var version: String
  public var author: String
  public var license: String?
  public var extends: String?
  public var palette: [String: String]
  public var slots: [String: SlotEntry]

  public init(
    schemaVersion: Int = ThemeManifest.currentSchemaVersion, id: String, name: String, version: String = "1.0.0",
    author: String = "", license: String? = nil, extends: String? = nil, palette: [String: String] = [:],
    slots: [String: SlotEntry] = [:]
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.version = version
    self.author = author
    self.license = license
    self.extends = extends
    self.palette = palette
    self.slots = slots
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, id, name, version, author, license, extends, palette, slots
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
    version = try c.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
    author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
    license = try c.decodeIfPresent(String.self, forKey: .license)
    extends = try c.decodeIfPresent(String.self, forKey: .extends)
    palette = try c.decodeIfPresent([String: String].self, forKey: .palette) ?? [:]
    slots = try c.decodeIfPresent([String: SlotEntry].self, forKey: .slots) ?? [:]
  }
}
