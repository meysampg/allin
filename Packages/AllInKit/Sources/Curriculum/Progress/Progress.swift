import Foundation

public struct NodeRecord: Codable, Sendable, Hashable {
  public var nodeID: String
  public var completed: Bool
  public var stars: Int
  public var bestScore: Double?

  public init(nodeID: String, completed: Bool = false, stars: Int = 0, bestScore: Double? = nil) {
    self.nodeID = nodeID
    self.completed = completed
    self.stars = stars
    self.bestScore = bestScore
  }
}

public struct ProgressSnapshot: Sendable, Hashable {
  public var nodes: [String: NodeRecord]

  public init(nodes: [String: NodeRecord] = [:]) { self.nodes = nodes }

  public func isCompleted(_ id: String) -> Bool { nodes[id]?.completed ?? false }
}

public enum NodeStatus: String, Sendable, Hashable { case locked, available, completed }

public enum VenueStatus: Sendable, Hashable {
  case comingSoon
  case locked(reason: String)
  case open(completed: Int, total: Int)
  case cleared(stars: Int)
}
