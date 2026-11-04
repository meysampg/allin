import Foundation

public struct SaveFile: Codable, Sendable, Equatable {
  public static let currentVersion = 1

  public var schemaVersion: Int
  public var exportedAt: Date
  public var profile: StoredProfile?
  public var skills: [StoredSkillState]
  public var decisionCards: [StoredDecisionCard]
  public var nodes: [StoredNodeProgress]
  public var sessions: [StoredSession]
  public var hands: [StoredHand]
  public var rivals: [StoredRivalKnowledge]
  public var playerModels: [StoredPlayerModelSnapshot]
  public var unlocks: [StoredUnlock]
  public var savedSpots: [StoredSavedSpot]

  public init(
    schemaVersion: Int = SaveFile.currentVersion, exportedAt: Date, profile: StoredProfile? = nil,
    skills: [StoredSkillState] = [], decisionCards: [StoredDecisionCard] = [], nodes: [StoredNodeProgress] = [],
    sessions: [StoredSession] = [], hands: [StoredHand] = [], rivals: [StoredRivalKnowledge] = [],
    playerModels: [StoredPlayerModelSnapshot] = [], unlocks: [StoredUnlock] = [],
    savedSpots: [StoredSavedSpot] = []
  ) {
    self.schemaVersion = schemaVersion
    self.exportedAt = exportedAt
    self.profile = profile
    self.skills = skills
    self.decisionCards = decisionCards
    self.nodes = nodes
    self.sessions = sessions
    self.hands = hands
    self.rivals = rivals
    self.playerModels = playerModels
    self.unlocks = unlocks
    self.savedSpots = savedSpots
  }
}

public enum SaveFileError: Error, Equatable {
  case unsupportedVersion(Int)
  case corrupt(String)
}

public enum SaveFileCodec {
  public static let fileExtension = "allinsave"

  public static func encode(_ file: SaveFile) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .deferredToDate
    return try encoder.encode(file)
  }

  public static func decode(_ data: Data) throws -> SaveFile {
    struct VersionProbe: Decodable { let schemaVersion: Int }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .deferredToDate
    do {
      let probe = try decoder.decode(VersionProbe.self, from: data)
      guard probe.schemaVersion <= SaveFile.currentVersion else {
        throw SaveFileError.unsupportedVersion(probe.schemaVersion)
      }
      return try decoder.decode(SaveFile.self, from: data)
    } catch let error as SaveFileError {
      throw error
    } catch {
      throw SaveFileError.corrupt(String(describing: error))
    }
  }
}
