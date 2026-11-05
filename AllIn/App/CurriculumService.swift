import AllInStore
import Curriculum
import Foundation
import OSLog
import Observation
import PokerAnalysis

/// The app's view of the curriculum: the loaded content pack, plus progress read from and written to the store.
@MainActor @Observable
final class CurriculumService {
  enum Source: Equatable {
    case curriculum(URL), fixture(URL), unavailable
  }

  let source: Source
  let library: ContentLibrary?
  let issues: [ContentIssue]
  /// Bumped after every write, so views observing the service refresh.
  private(set) var revision = 0
  /// Called after every write. Set by the app model.
  @ObservationIgnored var onChange: (() -> Void)?

  @ObservationIgnored private let progress: ProgressStore
  @ObservationIgnored private let scheduler = DrillScheduler()
  private static let log = Logger(subsystem: "app.allin", category: "Curriculum")

  /// The root is `contentDirectory` when it holds a `realm.json`, else `contentDirectory/fixtures/sample`.
  init(contentDirectory: URL, progress: ProgressStore) {
    self.progress = progress
    let root: URL
    let kind: (URL) -> Source
    if ContentLibrary.hasCurriculum(at: contentDirectory) {
      root = contentDirectory
      kind = { .curriculum($0) }
    } else {
      root = contentDirectory.appending(path: "fixtures/sample")
      kind = { .fixture($0) }
    }
    var found: [ContentIssue] = []
    do {
      let loaded = try ContentLibrary.load(
        root: root, charactersDirectory: contentDirectory.appending(path: "characters"))
      found = ContentValidator.structural(loaded)
      library = loaded
      source = kind(root)
    } catch {
      found = (error as? ContentLoadError)?.issues ?? []
      Self.log.error("content load failed: \(String(describing: error))")
      library = nil
      source = .unavailable
    }
    for issue in found { Self.log.error("\(issue.description)") }
    issues = found
  }

  // MARK: Reading

  func snapshot() -> ProgressSnapshot {
    _ = revision
    _ = progress.revision
    guard let library else { return ProgressSnapshot() }
    var nodes: [String: NodeRecord] = [:]
    for venue in library.venues {
      for node in venue.nodes {
        if let stored = progress.nodeProgress(node.id) {
          nodes[node.id] = NodeRecord(
            nodeID: node.id, completed: stored.statusRaw == "completed", stars: stored.stars,
            bestScore: stored.bestScore)
        }
      }
    }
    return ProgressSnapshot(nodes: nodes)
  }

  func skillModel() -> SkillModel {
    _ = revision
    _ = progress.revision
    guard let library else { return SkillModel() }
    var model = SkillModel()
    for skill in library.skills.skills {
      if let stored = progress.skillState(skill.id) {
        model.ratings[skill.id] = SkillRating(
          theta: stored.theta, evidence: Int(stored.evidence.rounded()), updatedAt: stored.updatedAt)
      }
    }
    return model
  }

  func venueStatus(_ venue: RealmVenue) -> VenueStatus {
    guard let library else { return .comingSoon }
    return UnlockResolver.status(of: venue, library: library, progress: snapshot())
  }

  func nodeStatus(_ node: VenueNode, in venue: Venue) -> NodeStatus {
    guard let library else { return .locked }
    return UnlockResolver.status(of: node, in: venue, library: library, progress: snapshot())
  }

  func nodeRecord(_ id: String) -> NodeRecord? { snapshot().nodes[id] }

  func meters(for venue: Venue) -> [(meter: VenueMeter, value: Double)] {
    guard let library else { return [] }
    let model = skillModel()
    return venue.meters.map { ($0, library.meterValue($0, skills: model)) }
  }

  func currentVenue() -> RealmVenue? {
    guard let library else { return nil }
    return UnlockResolver.currentVenue(library: library, progress: snapshot())
  }

  func currentNode(in venue: Venue) -> VenueNode? {
    guard let library else { return nil }
    return UnlockResolver.currentNode(in: venue, library: library, progress: snapshot())
  }

  /// "Village Tavern · 3/7"
  var careerProgressText: String {
    guard let library, let entry = currentVenue() ?? library.realm.venues.first(where: { $0.status == .open }),
      let venue = library.venue(entry.id)
    else { return "Career" }
    let snapshot = snapshot()
    let done = venue.nodes.filter { snapshot.isCompleted($0.id) }.count
    return "\(entry.name) · \(done)/\(venue.nodes.count)"
  }

  // MARK: Writing

  func recordDecision(
    skill: String, difficulty: Double, quality: Double, key: DecisionTypeKey, grade: Grade, fast: Bool,
    usedHint: Bool, instanceHash: String, at: Date
  ) {
    var model = SkillModel()
    if let stored = progress.skillState(skill) {
      model.ratings[skill] = SkillRating(
        theta: stored.theta, evidence: Int(stored.evidence.rounded()), updatedAt: stored.updatedAt)
    }
    let rating = model.record(skill: skill, difficulty: difficulty, quality: quality, at: at)
    progress.upsert(
      StoredSkillState(skillID: skill, theta: rating.theta, evidence: Double(rating.evidence), updatedAt: at))

    let previous = progress.decisionCard(key.rawValue).flatMap(Self.cardState)
    let next = scheduler.review(
      previous, key: key, grade: grade, fast: fast, usedHint: usedHint, instanceHash: instanceHash, now: at)
    progress.upsert(
      StoredDecisionCard(
        key: next.key.rawValue, stateRaw: next.card.state.rawValue, stability: next.card.stability,
        difficulty: next.card.difficulty, due: next.card.due, lastReview: next.card.lastReview, reps: next.card.reps,
        lapses: next.card.lapses, instanceHashes: next.instanceHashStrings))
    changed()
  }

  /// Keeps the highest stars and score seen.
  func completeNode(_ nodeID: String, stars: Int, score: Double?, at: Date) {
    let old = progress.nodeProgress(nodeID)
    progress.upsert(
      StoredNodeProgress(
        nodeID: nodeID, statusRaw: "completed", stars: max(stars, old?.stars ?? 0),
        bestScore: max(score ?? 0, old?.bestScore ?? 0)))
    changed()
  }

  func avoidHashes(now: Date) -> Set<String> {
    let cards = progress.exportSaveFile(now: now).decisionCards.compactMap(Self.cardState)
    return DrillScheduler.avoidSet(cards, now: now)
  }

  func drillPool() -> DrillPool {
    guard let library else { return DrillPool(entries: [], baseDifficulty: [:]) }
    return library.drillPool(unlockedVenues: UnlockResolver.unlockedVenueIDs(library: library, progress: snapshot()))
  }

  // MARK: Helpers

  private func changed() {
    revision += 1
    onChange?()
  }

  private static func cardState(_ stored: StoredDecisionCard) -> DecisionCardState? {
    DecisionCardState(
      stored: stored.key, stateRaw: stored.stateRaw, stability: stored.stability, difficulty: stored.difficulty,
      due: stored.due, lastReview: stored.lastReview, reps: stored.reps, lapses: stored.lapses,
      instanceHashes: stored.instanceHashes)
  }
}
