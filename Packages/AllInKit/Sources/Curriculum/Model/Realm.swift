import Foundation

public enum VenueIcon: String, ContentEnum { case village, townHall, castle, cave }

public enum RealmVenueStatus: String, ContentEnum { case open, comingSoon }

public struct VenueUnlock: Codable, Sendable, Hashable {
  public let afterVenue: String?

  public init(afterVenue: String? = nil) { self.afterVenue = afterVenue }
}

public struct RealmVenue: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let name: String
  public let icon: VenueIcon
  public let teaches: String
  public let status: RealmVenueStatus
  public let unlock: VenueUnlock?
  public let lockedText: String?

  public init(
    id: String, name: String, icon: VenueIcon, teaches: String, status: RealmVenueStatus,
    unlock: VenueUnlock? = nil, lockedText: String? = nil
  ) {
    self.id = id
    self.name = name
    self.icon = icon
    self.teaches = teaches
    self.status = status
    self.unlock = unlock
    self.lockedText = lockedText
  }
}

public struct Realm: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let venues: [RealmVenue]

  public init(schemaVersion: Int = ContentSchema.version, venues: [RealmVenue]) {
    self.schemaVersion = schemaVersion
    self.venues = venues
  }
}

public struct SkillAxis: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct SkillDefinition: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let name: String
  /// Axis id to weight.
  public let axes: [String: Double]
  public let baseDifficulty: Double

  public init(id: String, name: String, axes: [String: Double], baseDifficulty: Double) {
    self.id = id
    self.name = name
    self.axes = axes
    self.baseDifficulty = baseDifficulty
  }
}

public struct SkillCatalog: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let axes: [SkillAxis]
  public let skills: [SkillDefinition]

  public init(schemaVersion: Int = ContentSchema.version, axes: [SkillAxis], skills: [SkillDefinition]) {
    self.schemaVersion = schemaVersion
    self.axes = axes
    self.skills = skills
  }

  public func skill(_ id: String) -> SkillDefinition? { skills.first { $0.id == id } }

  public var baseDifficulties: [String: Double] {
    Dictionary(skills.map { ($0.id, $0.baseDifficulty) }, uniquingKeysWith: { first, _ in first })
  }

  /// Skill id to axis id to weight.
  public var axisWeights: [String: [String: Double]] {
    Dictionary(skills.map { ($0.id, $0.axes) }, uniquingKeysWith: { first, _ in first })
  }
}
