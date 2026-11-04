import Foundation
import SwiftData

/// All reads and writes of progress. Main-actor only; callers get value snapshots, never models.
@MainActor @Observable
public final class ProgressStore {
  typealias ProfileRow = AllInSchemaV1.ProfileEntity
  typealias SkillRow = AllInSchemaV1.SkillStateEntity
  typealias CardRow = AllInSchemaV1.DecisionCardEntity
  typealias NodeRow = AllInSchemaV1.NodeProgressEntity
  typealias SessionRow = AllInSchemaV1.SessionEntity
  typealias HandRow = AllInSchemaV1.HandEntity
  typealias RivalRow = AllInSchemaV1.RivalKnowledgeEntity
  typealias ModelRow = AllInSchemaV1.PlayerModelSnapshotEntity
  typealias UnlockRow = AllInSchemaV1.UnlockEntity
  typealias SpotRow = AllInSchemaV1.SavedSpotEntity

  public let container: ModelContainer
  /// Bumped after every write, so views observing the store refresh.
  public private(set) var revision = 0

  private var context: ModelContext { container.mainContext }

  public init(container: ModelContainer) {
    self.container = container
  }

  // MARK: Helpers

  private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
    (try? context.fetch(descriptor)) ?? []
  }

  private func save() {
    try? context.save()
    revision += 1
  }

  private func profileRow() -> ProfileRow? {
    var d = FetchDescriptor<ProfileRow>(predicate: #Predicate { $0.key == "main" })
    d.fetchLimit = 1
    return fetch(d).first
  }

  private func sessionRow(_ id: UUID) -> SessionRow? {
    var d = FetchDescriptor<SessionRow>(predicate: #Predicate { $0.id == id })
    d.fetchLimit = 1
    return fetch(d).first
  }

  // MARK: Profile

  public func profile() -> StoredProfile {
    if let row = profileRow() { return Self.value(row) }
    let row = ProfileRow(
      name: "Traveler", gold: 200, rank: "Tavern Regular", streakDays: 0, createdAt: .now, themeID: "default")
    context.insert(row)
    save()
    return Self.value(row)
  }

  public func updateProfile(_ change: (inout StoredProfile) -> Void) {
    _ = profile()
    guard let row = profileRow() else { return }
    var value = Self.value(row)
    change(&value)
    row.name = value.name
    row.gold = value.gold
    row.rank = value.rank
    row.streakDays = value.streakDays
    row.createdAt = value.createdAt
    row.themeID = value.themeID
    save()
  }

  // MARK: Sessions

  public func beginSession(kind: SessionKind, format: String, startedAt: Date = .now) -> UUID {
    let id = UUID()
    context.insert(
      SessionRow(
        id: id, kindRaw: kind.rawValue, format: format, startedAt: startedAt, endedAt: nil, hands: 0,
        decisionScore: nil, netChips: 0, luckChips: 0, assisted: false))
    save()
    return id
  }

  public func endSession(_ id: UUID, at: Date = .now, totals: SessionTotals) {
    guard let row = sessionRow(id) else { return }
    row.endedAt = at
    row.hands = totals.hands
    row.decisionScore = totals.decisionScore
    row.netChips = totals.netChips
    row.luckChips = totals.luckChips
    row.assisted = totals.assisted
    save()
  }

  public func session(_ id: UUID) -> StoredSession? {
    sessionRow(id).map(Self.value)
  }

  public func sessions(limit: Int = 50) -> [StoredSession] {
    var d = FetchDescriptor<SessionRow>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
    d.fetchLimit = limit
    return fetch(d).map(Self.value)
  }

  // MARK: Skills

  public func skillState(_ id: String) -> StoredSkillState? {
    var d = FetchDescriptor<SkillRow>(predicate: #Predicate { $0.skillID == id })
    d.fetchLimit = 1
    return fetch(d).first.map(Self.value)
  }

  public func upsert(_ v: StoredSkillState) {
    let id = v.skillID
    var d = FetchDescriptor<SkillRow>(predicate: #Predicate { $0.skillID == id })
    d.fetchLimit = 1
    if let row = fetch(d).first {
      row.theta = v.theta
      row.evidence = v.evidence
      row.updatedAt = v.updatedAt
    } else {
      context.insert(SkillRow(skillID: v.skillID, theta: v.theta, evidence: v.evidence, updatedAt: v.updatedAt))
    }
    save()
  }

  // MARK: Decision cards

  public func decisionCard(_ key: String) -> StoredDecisionCard? {
    var d = FetchDescriptor<CardRow>(predicate: #Predicate { $0.key == key })
    d.fetchLimit = 1
    return fetch(d).first.map(Self.value)
  }

  public func upsert(_ v: StoredDecisionCard) {
    let key = v.key
    var d = FetchDescriptor<CardRow>(predicate: #Predicate { $0.key == key })
    d.fetchLimit = 1
    let row: CardRow
    if let existing = fetch(d).first {
      row = existing
    } else {
      row = CardRow(
        key: v.key, stateRaw: 0, stability: 0, difficulty: 0, due: v.due, lastReview: nil, reps: 0, lapses: 0,
        instanceHashes: [])
      context.insert(row)
    }
    row.stateRaw = v.stateRaw
    row.stability = v.stability
    row.difficulty = v.difficulty
    row.due = v.due
    row.lastReview = v.lastReview
    row.reps = v.reps
    row.lapses = v.lapses
    row.instanceHashes = v.instanceHashes
    save()
  }

  // MARK: Nodes

  public func nodeProgress(_ id: String) -> StoredNodeProgress? {
    var d = FetchDescriptor<NodeRow>(predicate: #Predicate { $0.nodeID == id })
    d.fetchLimit = 1
    return fetch(d).first.map(Self.value)
  }

  public func upsert(_ v: StoredNodeProgress) {
    let id = v.nodeID
    var d = FetchDescriptor<NodeRow>(predicate: #Predicate { $0.nodeID == id })
    d.fetchLimit = 1
    if let row = fetch(d).first {
      row.statusRaw = v.statusRaw
      row.stars = v.stars
      row.bestScore = v.bestScore
    } else {
      context.insert(NodeRow(nodeID: v.nodeID, statusRaw: v.statusRaw, stars: v.stars, bestScore: v.bestScore))
    }
    save()
  }

  // MARK: Rivals and player model

  public func rival(_ id: String) -> StoredRivalKnowledge? {
    var d = FetchDescriptor<RivalRow>(predicate: #Predicate { $0.characterID == id })
    d.fetchLimit = 1
    return fetch(d).first.map(Self.value)
  }

  public func upsert(_ v: StoredRivalKnowledge) {
    let id = v.characterID
    var d = FetchDescriptor<RivalRow>(predicate: #Predicate { $0.characterID == id })
    d.fetchLimit = 1
    if let row = fetch(d).first {
      row.handsPlayed = v.handsPlayed
      row.statsJSON = v.statsJSON
      row.notes = v.notes
      row.autoNotes = v.autoNotes
    } else {
      context.insert(
        RivalRow(
          characterID: v.characterID, handsPlayed: v.handsPlayed, statsJSON: v.statsJSON, notes: v.notes,
          autoNotes: v.autoNotes))
    }
    save()
  }

  public func playerModel(_ id: String) -> StoredPlayerModelSnapshot? {
    var d = FetchDescriptor<ModelRow>(predicate: #Predicate { $0.id == id })
    d.fetchLimit = 1
    return fetch(d).first.map(Self.value)
  }

  public func upsert(_ v: StoredPlayerModelSnapshot) {
    let id = v.id
    var d = FetchDescriptor<ModelRow>(predicate: #Predicate { $0.id == id })
    d.fetchLimit = 1
    if let row = fetch(d).first {
      row.version = v.version
      row.blob = v.blob
      row.updatedAt = v.updatedAt
    } else {
      context.insert(ModelRow(id: v.id, version: v.version, blob: v.blob, updatedAt: v.updatedAt))
    }
    save()
  }

  // MARK: Unlocks and saved spots

  public func unlocks() -> [StoredUnlock] {
    fetch(FetchDescriptor<UnlockRow>(sortBy: [SortDescriptor(\.rewardID)])).map(Self.value)
  }

  /// Idempotent: unlocking twice keeps the first date.
  public func unlock(_ rewardID: String, at: Date = .now) {
    var d = FetchDescriptor<UnlockRow>(predicate: #Predicate { $0.rewardID == rewardID })
    d.fetchLimit = 1
    guard fetch(d).isEmpty else { return }
    context.insert(UnlockRow(rewardID: rewardID, unlockedAt: at))
    save()
  }

  public func savedSpots() -> [StoredSavedSpot] {
    fetch(FetchDescriptor<SpotRow>(sortBy: [SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.key)]))
      .map(Self.value)
  }

  public func saveSpot(_ v: StoredSavedSpot) {
    let key = v.key
    var d = FetchDescriptor<SpotRow>(predicate: #Predicate { $0.key == key })
    d.fetchLimit = 1
    if let row = fetch(d).first {
      row.handKey = v.handKey
      row.decisionIndex = v.decisionIndex
      row.streetRaw = v.streetRaw
      row.title = v.title
      row.createdAt = v.createdAt
    } else {
      context.insert(
        SpotRow(
          key: v.key, handKey: v.handKey, decisionIndex: v.decisionIndex, streetRaw: v.streetRaw, title: v.title,
          createdAt: v.createdAt))
    }
    save()
  }

  // MARK: Save file

  public func exportSaveFile(now: Date = .now) -> SaveFile {
    SaveFile(
      schemaVersion: SaveFile.currentVersion, exportedAt: now, profile: profileRow().map(Self.value),
      skills: fetch(FetchDescriptor<SkillRow>(sortBy: [SortDescriptor(\.skillID)])).map(Self.value),
      decisionCards: fetch(FetchDescriptor<CardRow>(sortBy: [SortDescriptor(\.key)])).map(Self.value),
      nodes: fetch(FetchDescriptor<NodeRow>(sortBy: [SortDescriptor(\.nodeID)])).map(Self.value),
      sessions: fetch(FetchDescriptor<SessionRow>(sortBy: [SortDescriptor(\.startedAt), SortDescriptor(\.id)]))
        .map(Self.value),
      hands: fetch(FetchDescriptor<HandRow>(sortBy: [SortDescriptor(\.key)])).compactMap(Self.value),
      rivals: fetch(FetchDescriptor<RivalRow>(sortBy: [SortDescriptor(\.characterID)])).map(Self.value),
      playerModels: fetch(FetchDescriptor<ModelRow>(sortBy: [SortDescriptor(\.id)])).map(Self.value),
      unlocks: unlocks(), savedSpots: fetch(FetchDescriptor<SpotRow>(sortBy: [SortDescriptor(\.key)])).map(Self.value))
  }

  /// Replaces ALL rows (hands included) in one save.
  public func importSaveFile(_ file: SaveFile) throws {
    guard file.schemaVersion <= SaveFile.currentVersion else {
      throw SaveFileError.unsupportedVersion(file.schemaVersion)
    }
    let encodedSeats = try file.hands.map { try HandArchive.encodeSeats($0.seats) }
    try context.transaction {
      try context.delete(model: ProfileRow.self)
      try context.delete(model: SkillRow.self)
      try context.delete(model: CardRow.self)
      try context.delete(model: NodeRow.self)
      try context.delete(model: SessionRow.self)
      try context.delete(model: HandRow.self)
      try context.delete(model: RivalRow.self)
      try context.delete(model: ModelRow.self)
      try context.delete(model: UnlockRow.self)
      try context.delete(model: SpotRow.self)

      if let p = file.profile {
        context.insert(
          ProfileRow(
            name: p.name, gold: p.gold, rank: p.rank, streakDays: p.streakDays, createdAt: p.createdAt,
            themeID: p.themeID))
      }
      for v in file.skills {
        context.insert(SkillRow(skillID: v.skillID, theta: v.theta, evidence: v.evidence, updatedAt: v.updatedAt))
      }
      for v in file.decisionCards {
        context.insert(
          CardRow(
            key: v.key, stateRaw: v.stateRaw, stability: v.stability, difficulty: v.difficulty, due: v.due,
            lastReview: v.lastReview, reps: v.reps, lapses: v.lapses, instanceHashes: v.instanceHashes))
      }
      for v in file.nodes {
        context.insert(NodeRow(nodeID: v.nodeID, statusRaw: v.statusRaw, stars: v.stars, bestScore: v.bestScore))
      }
      for v in file.sessions {
        context.insert(
          SessionRow(
            id: v.id, kindRaw: v.kind.rawValue, format: v.format, startedAt: v.startedAt, endedAt: v.endedAt,
            hands: v.hands, decisionScore: v.decisionScore, netChips: v.netChips, luckChips: v.luckChips,
            assisted: v.assisted))
      }
      for (v, seats) in zip(file.hands, encodedSeats) {
        context.insert(
          HandRow(
            key: v.key, sessionID: v.sessionID, handID: Int64(bitPattern: v.handID), playedAt: v.playedAt,
            heroSeat: v.heroSeat, seatsJSON: seats, log: v.log, strategySeed: Int64(bitPattern: v.strategySeed),
            netChips: v.netChips, potTotal: v.potTotal, bigBlind: v.bigBlind, graded: v.graded, good: v.good,
            smallMiss: v.smallMiss, leak: v.leak, evLossBB: v.evLossBB, luckChips: v.luckChips,
            decisionScore: v.decisionScore, weightedQuality: v.weightedQuality, weight: v.weight,
            analysis: v.analysis))
      }
      for v in file.rivals {
        context.insert(
          RivalRow(
            characterID: v.characterID, handsPlayed: v.handsPlayed, statsJSON: v.statsJSON, notes: v.notes,
            autoNotes: v.autoNotes))
      }
      for v in file.playerModels {
        context.insert(ModelRow(id: v.id, version: v.version, blob: v.blob, updatedAt: v.updatedAt))
      }
      for v in file.unlocks { context.insert(UnlockRow(rewardID: v.rewardID, unlockedAt: v.unlockedAt)) }
      for v in file.savedSpots {
        context.insert(
          SpotRow(
            key: v.key, handKey: v.handKey, decisionIndex: v.decisionIndex, streetRaw: v.streetRaw, title: v.title,
            createdAt: v.createdAt))
      }
    }
    revision += 1
  }

  // MARK: Entity to value

  private static func value(_ r: ProfileRow) -> StoredProfile {
    StoredProfile(
      name: r.name, gold: r.gold, rank: r.rank, streakDays: r.streakDays, createdAt: r.createdAt, themeID: r.themeID)
  }

  private static func value(_ r: SkillRow) -> StoredSkillState {
    StoredSkillState(skillID: r.skillID, theta: r.theta, evidence: r.evidence, updatedAt: r.updatedAt)
  }

  private static func value(_ r: CardRow) -> StoredDecisionCard {
    StoredDecisionCard(
      key: r.key, stateRaw: r.stateRaw, stability: r.stability, difficulty: r.difficulty, due: r.due,
      lastReview: r.lastReview, reps: r.reps, lapses: r.lapses, instanceHashes: r.instanceHashes)
  }

  private static func value(_ r: NodeRow) -> StoredNodeProgress {
    StoredNodeProgress(nodeID: r.nodeID, statusRaw: r.statusRaw, stars: r.stars, bestScore: r.bestScore)
  }

  private static func value(_ r: SessionRow) -> StoredSession {
    StoredSession(
      id: r.id, kind: SessionKind(rawValue: r.kindRaw) ?? .quick, format: r.format, startedAt: r.startedAt,
      endedAt: r.endedAt, hands: r.hands, decisionScore: r.decisionScore, netChips: r.netChips,
      luckChips: r.luckChips, assisted: r.assisted)
  }

  private static func value(_ r: HandRow) -> StoredHand? {
    guard let seats = try? HandArchive.decodeSeats(r.seatsJSON) else { return nil }
    return StoredHand(
      key: r.key, sessionID: r.sessionID, handID: UInt64(bitPattern: r.handID), playedAt: r.playedAt,
      heroSeat: r.heroSeat, seats: seats, log: r.log, strategySeed: UInt64(bitPattern: r.strategySeed),
      netChips: r.netChips, potTotal: r.potTotal, bigBlind: r.bigBlind, graded: r.graded, good: r.good,
      smallMiss: r.smallMiss, leak: r.leak, evLossBB: r.evLossBB, luckChips: r.luckChips,
      decisionScore: r.decisionScore, weightedQuality: r.weightedQuality, weight: r.weight, analysis: r.analysis)
  }

  private static func value(_ r: RivalRow) -> StoredRivalKnowledge {
    StoredRivalKnowledge(
      characterID: r.characterID, handsPlayed: r.handsPlayed, statsJSON: r.statsJSON, notes: r.notes,
      autoNotes: r.autoNotes)
  }

  private static func value(_ r: ModelRow) -> StoredPlayerModelSnapshot {
    StoredPlayerModelSnapshot(id: r.id, version: r.version, blob: r.blob, updatedAt: r.updatedAt)
  }

  private static func value(_ r: UnlockRow) -> StoredUnlock {
    StoredUnlock(rewardID: r.rewardID, unlockedAt: r.unlockedAt)
  }

  private static func value(_ r: SpotRow) -> StoredSavedSpot {
    StoredSavedSpot(
      key: r.key, handKey: r.handKey, decisionIndex: r.decisionIndex, streetRaw: r.streetRaw, title: r.title,
      createdAt: r.createdAt)
  }
}
