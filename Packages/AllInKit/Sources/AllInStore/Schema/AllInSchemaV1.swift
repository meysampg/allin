import Foundation
import SwiftData

/// Version 1 of the on-device progress schema. No relationships: rows are keyed by stable strings.
public enum AllInSchemaV1: VersionedSchema {
  public static let versionIdentifier = Schema.Version(1, 0, 0)
  public static var models: [any PersistentModel.Type] {
    [
      ProfileEntity.self, SkillStateEntity.self, DecisionCardEntity.self, NodeProgressEntity.self,
      SessionEntity.self, HandEntity.self, RivalKnowledgeEntity.self, PlayerModelSnapshotEntity.self,
      UnlockEntity.self, SavedSpotEntity.self,
    ]
  }
}

extension AllInSchemaV1 {
  @Model public final class ProfileEntity {
    @Attribute(.unique) public var key: String
    public var name: String
    public var gold: Int
    public var rank: String
    public var streakDays: Int
    public var createdAt: Date
    public var themeID: String

    public init(
      key: String = "main", name: String, gold: Int, rank: String, streakDays: Int, createdAt: Date,
      themeID: String
    ) {
      self.key = key
      self.name = name
      self.gold = gold
      self.rank = rank
      self.streakDays = streakDays
      self.createdAt = createdAt
      self.themeID = themeID
    }
  }

  @Model public final class SkillStateEntity {
    @Attribute(.unique) public var skillID: String
    public var theta: Double
    public var evidence: Double
    public var updatedAt: Date

    public init(skillID: String, theta: Double, evidence: Double, updatedAt: Date) {
      self.skillID = skillID
      self.theta = theta
      self.evidence = evidence
      self.updatedAt = updatedAt
    }
  }

  @Model public final class DecisionCardEntity {
    @Attribute(.unique) public var key: String
    public var stateRaw: Int
    public var stability: Double
    public var difficulty: Double
    public var due: Date
    public var lastReview: Date?
    public var reps: Int
    public var lapses: Int
    public var instanceHashes: [String]

    public init(
      key: String, stateRaw: Int, stability: Double, difficulty: Double, due: Date, lastReview: Date?,
      reps: Int, lapses: Int, instanceHashes: [String]
    ) {
      self.key = key
      self.stateRaw = stateRaw
      self.stability = stability
      self.difficulty = difficulty
      self.due = due
      self.lastReview = lastReview
      self.reps = reps
      self.lapses = lapses
      self.instanceHashes = instanceHashes
    }
  }

  @Model public final class NodeProgressEntity {
    @Attribute(.unique) public var nodeID: String
    public var statusRaw: String
    public var stars: Int
    public var bestScore: Double

    public init(nodeID: String, statusRaw: String, stars: Int, bestScore: Double) {
      self.nodeID = nodeID
      self.statusRaw = statusRaw
      self.stars = stars
      self.bestScore = bestScore
    }
  }

  @Model public final class SessionEntity {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var format: String
    public var startedAt: Date
    public var endedAt: Date?
    public var hands: Int
    public var decisionScore: Double?
    public var netChips: Int
    public var luckChips: Double
    public var assisted: Bool

    public init(
      id: UUID, kindRaw: String, format: String, startedAt: Date, endedAt: Date?, hands: Int,
      decisionScore: Double?, netChips: Int, luckChips: Double, assisted: Bool
    ) {
      self.id = id
      self.kindRaw = kindRaw
      self.format = format
      self.startedAt = startedAt
      self.endedAt = endedAt
      self.hands = hands
      self.decisionScore = decisionScore
      self.netChips = netChips
      self.luckChips = luckChips
      self.assisted = assisted
    }
  }

  @Model public final class HandEntity {
    #Index<HandEntity>([\.playedAt], [\.sessionID])
    @Attribute(.unique) public var key: String
    public var sessionID: UUID
    public var handID: Int64
    public var playedAt: Date
    public var heroSeat: Int
    public var seatsJSON: Data
    @Attribute(.externalStorage) public var log: Data
    public var strategySeed: Int64
    public var netChips: Int
    public var potTotal: Int
    public var bigBlind: Int
    public var graded: Bool
    public var good: Int
    public var smallMiss: Int
    public var leak: Int
    public var evLossBB: Double
    public var luckChips: Double
    public var decisionScore: Double?
    public var weightedQuality: Double
    public var weight: Double
    public var analysis: Data?

    public init(
      key: String, sessionID: UUID, handID: Int64, playedAt: Date, heroSeat: Int, seatsJSON: Data, log: Data,
      strategySeed: Int64, netChips: Int, potTotal: Int, bigBlind: Int, graded: Bool = false, good: Int = 0,
      smallMiss: Int = 0, leak: Int = 0, evLossBB: Double = 0, luckChips: Double = 0,
      decisionScore: Double? = nil, weightedQuality: Double = 0, weight: Double = 0, analysis: Data? = nil
    ) {
      self.key = key
      self.sessionID = sessionID
      self.handID = handID
      self.playedAt = playedAt
      self.heroSeat = heroSeat
      self.seatsJSON = seatsJSON
      self.log = log
      self.strategySeed = strategySeed
      self.netChips = netChips
      self.potTotal = potTotal
      self.bigBlind = bigBlind
      self.graded = graded
      self.good = good
      self.smallMiss = smallMiss
      self.leak = leak
      self.evLossBB = evLossBB
      self.luckChips = luckChips
      self.decisionScore = decisionScore
      self.weightedQuality = weightedQuality
      self.weight = weight
      self.analysis = analysis
    }
  }

  @Model public final class RivalKnowledgeEntity {
    @Attribute(.unique) public var characterID: String
    public var handsPlayed: Int
    public var statsJSON: Data
    public var notes: String
    public var autoNotes: [String]

    public init(characterID: String, handsPlayed: Int, statsJSON: Data, notes: String, autoNotes: [String]) {
      self.characterID = characterID
      self.handsPlayed = handsPlayed
      self.statsJSON = statsJSON
      self.notes = notes
      self.autoNotes = autoNotes
    }
  }

  @Model public final class PlayerModelSnapshotEntity {
    @Attribute(.unique) public var id: String
    public var version: Int
    public var blob: Data
    public var updatedAt: Date

    public init(id: String, version: Int, blob: Data, updatedAt: Date) {
      self.id = id
      self.version = version
      self.blob = blob
      self.updatedAt = updatedAt
    }
  }

  @Model public final class UnlockEntity {
    @Attribute(.unique) public var rewardID: String
    public var unlockedAt: Date

    public init(rewardID: String, unlockedAt: Date) {
      self.rewardID = rewardID
      self.unlockedAt = unlockedAt
    }
  }

  @Model public final class SavedSpotEntity {
    @Attribute(.unique) public var key: String
    public var handKey: String
    public var decisionIndex: Int
    public var streetRaw: String
    public var title: String
    public var createdAt: Date

    public init(
      key: String, handKey: String, decisionIndex: Int, streetRaw: String, title: String, createdAt: Date
    ) {
      self.key = key
      self.handKey = handKey
      self.decisionIndex = decisionIndex
      self.streetRaw = streetRaw
      self.title = title
      self.createdAt = createdAt
    }
  }
}
