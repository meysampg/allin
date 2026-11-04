import Foundation
import PokerCore
import SwiftData

/// Hand histories (compressed event logs) and their grades. Main-actor; shares the container's `mainContext`.
@MainActor @Observable
public final class HandArchive {
  typealias Entity = AllInSchemaV1.HandEntity

  private let container: ModelContainer
  /// Bumped after every write, so views observing the archive refresh.
  public private(set) var revision = 0

  private var context: ModelContext { container.mainContext }

  public init(container: ModelContainer) {
    self.container = container
  }

  private func entity(_ key: ArchiveKey) throws -> Entity? {
    let raw = key.rawValue
    var descriptor = FetchDescriptor<Entity>(predicate: #Predicate { $0.key == raw })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  /// Upserts by key and resets the grade (`graded = false`).
  public func save(_ input: ArchivedHandInput) throws {
    let log = try HandLogCodec.encode(input.log)
    let seats = try Self.encodeSeats(input.seats)
    let seed = Int64(bitPattern: input.strategySeed)
    let row: Entity
    if let existing = try entity(input.key) {
      row = existing
      existing.sessionID = input.key.sessionID
      existing.handID = Int64(bitPattern: input.key.handID.rawValue)
      existing.playedAt = input.playedAt
      existing.heroSeat = input.heroSeat
      existing.seatsJSON = seats
      existing.log = log
      existing.strategySeed = seed
      existing.netChips = input.netChips
      existing.potTotal = input.potTotal
      existing.bigBlind = input.bigBlind
    } else {
      row = Entity(
        key: input.key.rawValue, sessionID: input.key.sessionID,
        handID: Int64(bitPattern: input.key.handID.rawValue), playedAt: input.playedAt, heroSeat: input.heroSeat,
        seatsJSON: seats, log: log, strategySeed: seed, netChips: input.netChips, potTotal: input.potTotal,
        bigBlind: input.bigBlind)
      context.insert(row)
    }
    row.graded = false
    row.good = 0
    row.smallMiss = 0
    row.leak = 0
    row.evLossBB = 0
    row.luckChips = 0
    row.decisionScore = nil
    row.weightedQuality = 0
    row.weight = 0
    row.analysis = nil
    try context.save()
    revision += 1
  }

  /// Stores the analysis blob and grade totals; a missing hand is ignored.
  public func attachAnalysis(_ key: ArchiveKey, analysis: Data, grades: HandGradeSummary) throws {
    guard let row = try entity(key) else { return }
    row.analysis = analysis
    row.graded = true
    row.good = grades.good
    row.smallMiss = grades.smallMiss
    row.leak = grades.leak
    row.evLossBB = grades.evLossBB
    row.luckChips = grades.luckChips
    row.weightedQuality = grades.weightedQuality
    row.weight = grades.weight
    row.decisionScore = grades.decisionScore
    try context.save()
    revision += 1
  }

  public func hand(_ key: ArchiveKey) throws -> ArchivedHand? {
    guard let row = try entity(key) else { return nil }
    return try Self.value(row)
  }

  public func latest(sessionID: UUID? = nil) throws -> ArchivedHand? {
    var descriptor = Self.newestFirst(sessionID: sessionID)
    descriptor.fetchLimit = 1
    guard let row = try context.fetch(descriptor).first else { return nil }
    return try Self.value(row)
  }

  /// Newest first, without decoding any log.
  public func summaries(sessionID: UUID? = nil, limit: Int = 200) -> [StoredHandSummary] {
    var descriptor = Self.newestFirst(sessionID: sessionID)
    descriptor.fetchLimit = limit
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.compactMap { row in
      guard let key = ArchiveKey(rawValue: row.key) else { return nil }
      return StoredHandSummary(
        key: key, playedAt: row.playedAt, heroSeat: row.heroSeat, netChips: row.netChips, potTotal: row.potTotal,
        bigBlind: row.bigBlind, grades: Self.grades(row))
    }
  }

  public func count(sessionID: UUID? = nil) -> Int {
    let descriptor: FetchDescriptor<Entity>
    if let sessionID {
      descriptor = FetchDescriptor<Entity>(predicate: #Predicate { $0.sessionID == sessionID })
    } else {
      descriptor = FetchDescriptor<Entity>()
    }
    return (try? context.fetchCount(descriptor)) ?? 0
  }

  // MARK: Helpers

  private static func newestFirst(sessionID: UUID?) -> FetchDescriptor<Entity> {
    let sort = [SortDescriptor(\Entity.playedAt, order: .reverse), SortDescriptor(\Entity.handID, order: .reverse)]
    if let sessionID {
      return FetchDescriptor<Entity>(predicate: #Predicate { $0.sessionID == sessionID }, sortBy: sort)
    }
    return FetchDescriptor<Entity>(sortBy: sort)
  }

  static func encodeSeats(_ seats: [ArchivedSeat]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(seats)
  }

  static func decodeSeats(_ data: Data) throws -> [ArchivedSeat] {
    try JSONDecoder().decode([ArchivedSeat].self, from: data)
  }

  private static func grades(_ row: Entity) -> HandGradeSummary? {
    guard row.graded else { return nil }
    return HandGradeSummary(
      good: row.good, smallMiss: row.smallMiss, leak: row.leak, evLossBB: row.evLossBB, luckChips: row.luckChips,
      weightedQuality: row.weightedQuality, weight: row.weight, decisionScore: row.decisionScore)
  }

  private static func value(_ row: Entity) throws -> ArchivedHand? {
    guard let key = ArchiveKey(rawValue: row.key) else { return nil }
    return ArchivedHand(
      key: key, playedAt: row.playedAt, heroSeat: row.heroSeat, seats: try decodeSeats(row.seatsJSON),
      log: try HandLogCodec.decode(row.log), strategySeed: UInt64(bitPattern: row.strategySeed),
      netChips: row.netChips, potTotal: row.potTotal, bigBlind: row.bigBlind, grades: grades(row),
      analysis: row.analysis)
  }
}
