import PokerCore

public struct LeakExample: Codable, Sendable, Hashable {
  public let handKey: String
  public let decisionIndex: Int
  public let evLossBB: Double

  public init(handKey: String, decisionIndex: Int, evLossBB: Double) {
    self.handKey = handKey
    self.decisionIndex = decisionIndex
    self.evLossBB = evLossBB
  }
}

public struct Leak: Codable, Sendable, Hashable, Identifiable {
  public var id: String {
    "\(kind.street.rawValue).\(kind.facing.rawValue).\(kind.chosen.rawValue)>\(kind.best.rawValue)"
  }
  public let kind: DecisionKind
  /// "Turn: checking when betting earns more".
  public let title: String
  public let occurrences: Int
  public let opportunities: Int
  public let evLostBB: Double
  public let examples: [LeakExample]

  public init(
    kind: DecisionKind, title: String, occurrences: Int, opportunities: Int, evLostBB: Double,
    examples: [LeakExample]
  ) {
    self.kind = kind
    self.title = title
    self.occurrences = occurrences
    self.opportunities = opportunities
    self.evLostBB = evLostBB
    self.examples = examples
  }
}

/// Finds repeated mistakes across hands: groups decisions that were not good and chose another class of action
/// than the best one by (street, facing, chosen class, best class).
public struct LeakDetector: Sendable {
  public let minOccurrences: Int
  private var occurrences: [DecisionKind: Int] = [:]
  private var lost: [DecisionKind: Double] = [:]
  private var examples: [DecisionKind: [LeakExample]] = [:]
  private var opportunities: [Situation: Int] = [:]

  private struct Situation: Hashable {
    let street: Street
    let facing: Facing
  }

  public init(minOccurrences: Int = 2) { self.minOccurrences = minOccurrences }

  /// Every non-good decision with a chosen class different from the best class counts toward its `DecisionKind`;
  /// every decision counts as an opportunity for its (street, facing).
  public mutating func add(_ analysis: HandAnalysis, handKey: String) {
    for decision in analysis.decisions {
      let kind = decision.kind
      opportunities[Situation(street: kind.street, facing: kind.facing), default: 0] += 1
      guard decision.graded.grade != .good, kind.chosen != kind.best else { continue }
      occurrences[kind, default: 0] += 1
      lost[kind, default: 0] += decision.graded.evLossBB
      var list = examples[kind, default: []]
      list.append(LeakExample(handKey: handKey, decisionIndex: decision.index, evLossBB: decision.graded.evLossBB))
      list.sort { a, b in
        if a.evLossBB != b.evLossBB { return a.evLossBB > b.evLossBB }
        if a.handKey != b.handKey { return a.handKey < b.handKey }
        return a.decisionIndex < b.decisionIndex
      }
      examples[kind] = Array(list.prefix(5))
    }
  }

  /// By EV lost, descending, then id.
  public func leaks(top: Int = 5) -> [Leak] {
    let found = occurrences.filter { $0.value >= minOccurrences }.map { kind, count in
      Leak(
        kind: kind, title: Self.title(kind), occurrences: count,
        opportunities: opportunities[Situation(street: kind.street, facing: kind.facing)] ?? count,
        evLostBB: lost[kind] ?? 0, examples: examples[kind] ?? [])
    }
    let sorted = found.sorted { a, b in
      a.evLostBB != b.evLostBB ? a.evLostBB > b.evLostBB : a.id < b.id
    }
    return Array(sorted.prefix(max(top, 0)))
  }

  static func title(_ kind: DecisionKind) -> String {
    let street = kind.street.rawValue.prefix(1).uppercased() + kind.street.rawValue.dropFirst()
    let facingNothing = kind.facing == .none
    let chosen: String
    switch kind.chosen {
    case .fold: chosen = "folding"
    case .passive: chosen = facingNothing ? "checking" : "calling"
    case .aggressive: chosen = kind.facing == .raise || kind.facing == .bet ? "raising" : "betting"
    }
    let tail: String
    switch kind.best {
    case .fold: tail = "folding is better"
    case .passive: tail = facingNothing ? "checking is better" : "calling is better"
    case .aggressive: tail = kind.facing == .none ? "betting earns more" : "raising earns more"
    }
    return "\(street): \(chosen) when \(tail)"
  }
}
