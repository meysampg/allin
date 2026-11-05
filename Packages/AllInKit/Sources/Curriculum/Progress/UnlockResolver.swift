import Foundation

/// Which nodes and venues are playable, from the content and the player's progress.
public enum UnlockResolver {
  public static func status(
    of node: VenueNode, in venue: Venue, library: ContentLibrary, progress: ProgressSnapshot
  ) -> NodeStatus {
    if progress.isCompleted(node.id) { return .completed }
    if let entry = library.realmVenue(venue.id), !isUnlocked(entry, library: library, progress: progress) {
      return .locked
    }
    let ready = venue.prerequisites(of: node).allSatisfy { progress.isCompleted($0) }
    return ready ? .available : .locked
  }

  public static func status(of venue: RealmVenue, library: ContentLibrary, progress: ProgressSnapshot) -> VenueStatus {
    guard venue.status == .open else { return .comingSoon }
    if let reason = lockReason(venue, library: library, progress: progress) { return .locked(reason: reason) }
    guard let content = library.venue(venue.id) else { return .comingSoon }
    if isCleared(content, progress: progress) { return .cleared(stars: clearedStars(content, progress: progress)) }
    let done = content.nodes.filter { progress.isCompleted($0.id) }.count
    return .open(completed: done, total: content.nodes.count)
  }

  /// The boss node is completed, else every node is.
  public static func isCleared(_ venue: Venue, progress: ProgressSnapshot) -> Bool {
    if let boss = venue.nodes.first(where: { $0.kind == .boss }) { return progress.isCompleted(boss.id) }
    return !venue.nodes.isEmpty && venue.nodes.allSatisfy { progress.isCompleted($0.id) }
  }

  /// The first node that is available and not completed.
  public static func currentNode(in venue: Venue, library: ContentLibrary, progress: ProgressSnapshot) -> VenueNode? {
    venue.nodes.first { status(of: $0, in: venue, library: library, progress: progress) == .available }
  }

  /// The first open, unlocked, not yet cleared venue.
  public static func currentVenue(library: ContentLibrary, progress: ProgressSnapshot) -> RealmVenue? {
    library.realm.venues.first {
      if case .open = status(of: $0, library: library, progress: progress) { return true }
      return false
    }
  }

  /// Open or cleared venues, in realm order.
  public static func unlockedVenueIDs(library: ContentLibrary, progress: ProgressSnapshot) -> [String] {
    library.realm.venues.filter {
      switch status(of: $0, library: library, progress: progress) {
      case .open, .cleared: true
      case .comingSoon, .locked: false
      }
    }.map(\.id)
  }

  // MARK: Helpers

  private static func isUnlocked(_ venue: RealmVenue, library: ContentLibrary, progress: ProgressSnapshot) -> Bool {
    venue.status == .open && lockReason(venue, library: library, progress: progress) == nil
  }

  /// nil when the venue's `afterVenue` (if any) is cleared.
  private static func lockReason(_ venue: RealmVenue, library: ContentLibrary, progress: ProgressSnapshot) -> String? {
    guard let previousID = venue.unlock?.afterVenue else { return nil }
    if let previous = library.venue(previousID), isCleared(previous, progress: progress) { return nil }
    if let text = venue.lockedText { return text }
    return "beat the \(library.realmVenue(previousID)?.name ?? previousID) boss"
  }

  /// The boss node's stars, else the lowest star count among the nodes.
  private static func clearedStars(_ venue: Venue, progress: ProgressSnapshot) -> Int {
    if let boss = venue.nodes.first(where: { $0.kind == .boss }) { return progress.nodes[boss.id]?.stars ?? 0 }
    return venue.nodes.map { progress.nodes[$0.id]?.stars ?? 0 }.min() ?? 0
  }
}

public enum LessonScoring {
  /// rule = 3 if `three` holds, else 2 if `two` holds, else 1. A rule holds when
  /// (rule.puzzleGood != true || puzzleGood == true) && applyGood >= (rule.applyGood ?? 0).
  /// Result = max(1, rule - hintCost * hintsUsed).
  public static func stars(
    _ spec: LessonStars, puzzleGood: Bool?, applyGood: Int, applyTotal: Int, hintsUsed: Int
  ) -> Int {
    func holds(_ rule: StarRule) -> Bool {
      (rule.puzzleGood != true || puzzleGood == true) && applyGood >= (rule.applyGood ?? 0)
    }
    let base = holds(spec.three) ? 3 : (holds(spec.two) ? 2 : 1)
    return max(1, base - spec.hintCost * hintsUsed)
  }

  /// 80% or more is 3 stars, 60% or more is 2, else 1.
  public static func drillStars(good: Int, total: Int) -> Int {
    guard total > 0 else { return 1 }
    return good * 5 >= total * 4 ? 3 : (good * 5 >= total * 3 ? 2 : 1)
  }
}
