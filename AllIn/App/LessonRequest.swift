import Foundation

/// What the lesson player is asked to play: a lesson or a drill from a venue node.
struct LessonRequest: Hashable, Sendable {
  enum Content: Hashable, Sendable { case lesson(String), drill(String) }

  let venueID: String
  let nodeID: String
  let content: Content
  let seed: UInt64
  /// 1-based; demo and debug only.
  var startStep: Int? = nil
}
