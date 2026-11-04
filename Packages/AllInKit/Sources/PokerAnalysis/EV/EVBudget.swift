/// How much work an EV estimate may do.
public struct EVBudget: Codable, Sendable, Hashable {
  public var rolloutsPerCandidate: Int
  /// Streets played with real policies, counting the decision's street. At the first decision on a
  /// later street, everyone checks down to showdown. Int.max = play to the end.
  public var policyStreets: Int
  public var chunks: Int

  public init(rolloutsPerCandidate: Int, policyStreets: Int, chunks: Int = 8) {
    self.rolloutsPerCandidate = rolloutsPerCandidate
    self.policyStreets = policyStreets
    self.chunks = chunks
  }

  public static let standard = EVBudget(rolloutsPerCandidate: 400, policyStreets: 2)
  public static let demo = EVBudget(rolloutsPerCandidate: 96, policyStreets: 2)
  public static let thorough = EVBudget(rolloutsPerCandidate: 4_000, policyStreets: .max)
  public static let test = EVBudget(rolloutsPerCandidate: 24, policyStreets: 1, chunks: 2)
}
