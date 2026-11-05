import AllInStore
import Foundation
import OSLog
import Observation
import PokerAI
import PokerAnalysis
import PokerCore
import PokerHost

extension HandGradeSummary {
  init(from analysis: HandAnalysis) {
    self.init(
      good: analysis.counts.good, smallMiss: analysis.counts.smallMiss, leak: analysis.counts.leak,
      evLossBB: analysis.evLossBB, luckChips: analysis.luck.luckChips, weightedQuality: analysis.weightedQuality,
      weight: analysis.weight, decisionScore: analysis.decisionScore)
  }
}

/// Archives every finished hand, grades it in the background (serially, off the main actor) and keeps the session
/// records.
@MainActor @Observable
final class HandAnalysisService {
  private struct SessionState {
    var setup: TableSetup
    var scorer = SessionScorer()
    var hands = 0
    var netChips = 0
  }

  private struct GradingJob: Sendable {
    let key: ArchiveKey
    let sessionID: UUID
    let log: EventLog
    let heroSeat: Int
    let opponentIDs: [Int: String]
    let patronSeed: UInt64
  }

  private(set) var pending: Set<ArchiveKey> = []
  private(set) var revision = 0

  @ObservationIgnored private let archive: HandArchive
  @ObservationIgnored private let progress: ProgressStore
  @ObservationIgnored private let charactersDirectory: URL
  @ObservationIgnored private let characters: [BotCharacter]
  @ObservationIgnored private let budget: EVBudget
  @ObservationIgnored private var sessions: [UUID: SessionState] = [:]
  @ObservationIgnored private var cache: [ArchiveKey: HandAnalysis] = [:]
  @ObservationIgnored private var demoCache: [UInt64: (GoldenHand, HandAnalysis)] = [:]
  @ObservationIgnored private var tail: Task<Void, Never>?

  private static let log = Logger(subsystem: "app.allin", category: "HandAnalysisService")

  init(
    archive: HandArchive, progress: ProgressStore, charactersDirectory: URL, characters: [BotCharacter],
    budget: EVBudget
  ) {
    self.archive = archive
    self.progress = progress
    self.charactersDirectory = charactersDirectory
    self.characters = characters
    self.budget = budget
  }

  // MARK: Sessions

  func beginSession(setup: TableSetup) -> UUID {
    let id = progress.beginSession(kind: .quick, format: setup.format.rawValue)
    sessions[id] = SessionState(setup: setup)
    return id
  }

  /// Waits for the session's hands to be graded, then writes the session record.
  func endSession(_ id: UUID) {
    let previous = tail
    tail = Task { [weak self] in
      await previous?.value
      guard let self, let state = sessions.removeValue(forKey: id) else { return }
      let score = state.scorer.score
      progress.endSession(
        id,
        totals: SessionTotals(
          hands: state.hands, decisionScore: score.decisionScore, netChips: state.netChips,
          luckChips: score.luckChips))
    }
  }

  // MARK: Recording and grading

  @discardableResult
  func record(_ outcome: HandOutcome, setup: TableSetup, sessionID: UUID) -> ArchiveKey {
    let key = ArchiveKey(sessionID: sessionID, handID: outcome.handID)
    let hero = setup.heroSeat
    let input = ArchivedHandInput(
      key: key, playedAt: .now, heroSeat: hero, seats: archivedSeats(setup: setup), log: outcome.log,
      strategySeed: setup.seed, netChips: outcome.result.netChips(of: hero) ?? 0,
      potTotal: outcome.result.contributions.reduce(0) { $0 + $1.amount }, bigBlind: setup.bigBlind)
    do {
      try archive.save(input)
    } catch {
      Self.log.error("could not archive hand \(key.rawValue): \(String(describing: error))")
      return key
    }
    sessions[sessionID]?.hands += 1
    sessions[sessionID]?.netChips += input.netChips
    cache[key] = nil
    pending.insert(key)
    var opponentIDs: [Int: String] = [:]
    for seat in 0..<setup.seatCount where seat != hero {
      opponentIDs[seat] = setup.opponentIDs.indices.contains(seat - 1) ? setup.opponentIDs[seat - 1] : "oryn"
    }
    let job = GradingJob(
      key: key, sessionID: sessionID, log: outcome.log, heroSeat: hero, opponentIDs: opponentIDs,
      patronSeed: setup.seed)
    enqueue(job)
    return key
  }

  func analysis(for key: ArchiveKey) -> HandAnalysis? {
    if let cached = cache[key] { return cached }
    guard let data = try? archive.hand(key)?.analysis,
      let decoded = try? JSONDecoder().decode(HandAnalysis.self, from: data)
    else { return nil }
    cache[key] = decoded
    return decoded
  }

  func analyzeDemo(seed: UInt64) async throws -> (GoldenHand, HandAnalysis) {
    if let cached = demoCache[seed] { return cached }
    let directory = charactersDirectory
    let characters = characters
    let result = try await Task.detached(priority: .utility) {
      let golden = try GoldenHands.reviewDemo()
      let analysis = try await Self.analyze(
        log: golden.log, heroSeat: golden.heroSeat, opponentIDs: golden.characters, patronSeed: seed,
        directory: directory, characters: characters, budget: .demo)
      return (golden, analysis)
    }.value
    demoCache[seed] = result
    return result
  }

  private func enqueue(_ job: GradingJob) {
    let previous = tail
    let directory = charactersDirectory
    let characters = characters
    let budget = budget
    tail = Task { [weak self] in
      await previous?.value
      let outcome = await Task.detached(priority: .utility) { () -> Result<(HandAnalysis, Data), any Error> in
        do {
          let analysis = try await Self.analyze(
            log: job.log, heroSeat: job.heroSeat, opponentIDs: job.opponentIDs, patronSeed: job.patronSeed,
            directory: directory, characters: characters, budget: budget)
          return .success((analysis, try JSONEncoder().encode(analysis)))
        } catch {
          return .failure(error)
        }
      }.value
      self?.finish(job, outcome)
    }
  }

  private func finish(_ job: GradingJob, _ outcome: Result<(HandAnalysis, Data), any Error>) {
    pending.remove(job.key)
    switch outcome {
    case .success(let (analysis, data)):
      cache[job.key] = analysis
      sessions[job.sessionID]?.scorer.add(analysis)
      do {
        try archive.attachAnalysis(job.key, analysis: data, grades: HandGradeSummary(from: analysis))
      } catch {
        Self.log.error("could not store analysis: \(String(describing: error))")
      }
    case .failure(let error):
      Self.log.error("grading failed for \(job.key.rawValue): \(String(describing: error))")
    }
    revision += 1
  }

  /// Same strategies as the session: the roster with the session's patron seed, seat to id as the table mapped it.
  nonisolated private static func analyze(
    log: EventLog, heroSeat: Int, opponentIDs: [Int: String], patronSeed: UInt64, directory: URL,
    characters: [BotCharacter], budget: EVBudget
  ) async throws -> HandAnalysis {
    let roster = try BotRoster.load(directory: directory, patronSeed: patronSeed)
    var strategies: [Int: any StrategyProvider] = [:]
    var names: [Int: String] = [:]
    var styles: [Int: String] = [:]
    for (seat, id) in opponentIDs {
      guard let bot = roster.first(where: { $0.id == id }) ?? roster.first else { continue }
      strategies[seat] = bot.strategy
      let character = characters.first { $0.id == id }
      names[seat] = character?.name ?? bot.name
      if let character { styles[seat] = character.style }
    }
    return try await HandAnalyzer.analyze(
      HandAnalysisInput(
        log: log, heroSeat: heroSeat, opponents: strategies, heroContinuation: BaselineStrategy(),
        seatNames: names, seatStyles: styles, budget: budget))
  }

  private func archivedSeats(setup: TableSetup) -> [ArchivedSeat] {
    (0..<setup.seatCount).map { seat in
      if seat == setup.heroSeat { return ArchivedSeat(seat: seat, name: "You", characterID: "you", isHero: true) }
      let id = setup.opponentIDs.indices.contains(seat - 1) ? setup.opponentIDs[seat - 1] : nil
      let character = id.flatMap { id in characters.first { $0.id == id } }
      return ArchivedSeat(
        seat: seat, name: character?.name ?? id?.capitalized ?? "Seat \(seat)", characterID: id,
        style: character?.style)
    }
  }
}
