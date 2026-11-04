import PokerCore

public enum EVMethod: String, Codable, Sendable { case exactFold, closedForm, rollout }

public struct CandidateEV: Codable, Sendable, Hashable {
  public let action: Action
  /// `ActionLabel.long`.
  public let label: String
  /// `ActionLabel.short` (chart axis).
  public let shortLabel: String
  /// Mean of (heroFinalStack - heroStackAtDecision) / bigBlind; fold = 0 exactly.
  public let evBB: Double
  /// In big blinds; 0 for exact values.
  public let standardError: Double
  public let samples: Int
  public let method: EVMethod

  public init(
    action: Action, label: String, shortLabel: String, evBB: Double, standardError: Double, samples: Int,
    method: EVMethod
  ) {
    self.action = action
    self.label = label
    self.shortLabel = shortLabel
    self.evBB = evBB
    self.standardError = standardError
    self.samples = samples
    self.method = method
  }
}

public struct ActionEVResult: Codable, Sendable, Hashable {
  /// Order: fold, check/call, bets/raises ascending, all-in.
  public let candidates: [CandidateEV]

  public init(candidates: [CandidateEV]) {
    self.candidates = candidates
  }

  /// Max `evBB`; ties go to the earlier candidate.
  public var best: CandidateEV {
    var best = candidates[0]
    for c in candidates.dropFirst() where c.evBB > best.evBB { best = c }
    return best
  }

  /// Descending `evBB`, stable.
  public var ranked: [CandidateEV] {
    candidates.enumerated().sorted { a, b in
      a.element.evBB != b.element.evBB ? a.element.evBB > b.element.evBB : a.offset < b.offset
    }.map(\.element)
  }

  public func candidate(for action: Action) -> CandidateEV? {
    candidates.first { $0.action == action }
  }
}
