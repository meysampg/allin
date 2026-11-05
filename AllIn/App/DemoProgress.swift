import AllInStore
import Curriculum
import Foundation

/// Seeded progress for screenshots and UI tests. Only ever written to the in-memory demo store.
enum DemoProgress {
  static let stars = [3, 2, 3]
  static let meterValues = [0.80, 0.60, 0.20, 0.0]

  /// First open venue: nodes 1 to 3 completed with 3, 2 and 3 stars; meters 1 to 4 at 80, 60, 20 and 0 percent.
  @MainActor static func seed(_ progress: ProgressStore, library: ContentLibrary) {
    guard let entry = library.realm.venues.first(where: { $0.status == .open }), let venue = library.venue(entry.id)
    else { return }
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    for (node, stars) in zip(venue.nodes, stars) {
      progress.upsert(StoredNodeProgress(nodeID: node.id, statusRaw: "completed", stars: stars, bestScore: 0.9))
    }
    let base = library.skills.baseDifficulties
    for (meter, value) in zip(venue.meters, meterValues) where value > 0 {
      for skill in meter.skills {
        let theta = SkillModel.theta(forMeter: value, baseDifficulty: base[skill] ?? 0.5)
        progress.upsert(StoredSkillState(skillID: skill, theta: theta, evidence: 10, updatedAt: now))
      }
    }
  }
}
