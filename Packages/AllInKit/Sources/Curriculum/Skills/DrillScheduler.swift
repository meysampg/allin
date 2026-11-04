import Foundation
import PokerAnalysis
import PokerEquity

public struct RecentInstance: Codable, Sendable, Hashable {
  public let hash: String
  public let day: DayKey

  public init(hash: String, day: DayKey) {
    self.hash = hash
    self.day = day
  }

  /// Parses "hash|yyyy-MM-dd" (split at the last "|").
  public init?(rawValue: String) {
    guard let i = rawValue.lastIndex(of: "|"),
      let day = DayKey(string: String(rawValue[rawValue.index(after: i)...]))
    else { return nil }
    self.hash = String(rawValue[rawValue.startIndex..<i])
    self.day = day
  }

  public var rawValue: String { "\(hash)|\(day.string)" }
}

public struct DecisionCardState: Codable, Sendable, Hashable {
  public var key: DecisionTypeKey
  public var card: FSRSCard
  public var recent: [RecentInstance]

  public init(key: DecisionTypeKey, card: FSRSCard, recent: [RecentInstance] = []) {
    self.key = key
    self.card = card
    self.recent = recent
  }
}

public struct DrillPool: Sendable, Hashable {
  public struct Entry: Sendable, Hashable {
    public let templateID: String
    public let skill: String
    public let order: Int

    public init(templateID: String, skill: String, order: Int) {
      self.templateID = templateID
      self.skill = skill
      self.order = order
    }
  }

  public var entries: [Entry]
  public var baseDifficulty: [String: Double]

  public init(entries: [Entry], baseDifficulty: [String: Double]) {
    self.entries = entries
    self.baseDifficulty = baseDifficulty
  }
}

public enum DrillReason: Sendable, Hashable {
  case due(DecisionTypeKey)
  case weakSkill(String)
  case newMaterial(String)
}

public struct DrillPick: Sendable, Hashable {
  public let templateID: String
  public let targetAnswerClass: String?
  public let skill: String
  public let reason: DrillReason

  public init(templateID: String, targetAnswerClass: String?, skill: String, reason: DrillReason) {
    self.templateID = templateID
    self.targetAnswerClass = targetAnswerClass
    self.skill = skill
    self.reason = reason
  }
}

public struct DrillScheduler: Sendable {
  public static let fastThreshold: Duration = .seconds(8)
  public static let noRepeatDays = 60

  public let scheduler: FSRSScheduler

  public init(scheduler: FSRSScheduler = FSRSScheduler(calendar: DayKey.gregorian())) {
    self.scheduler = scheduler
  }

  /// Due cards first, then weak skills and new material alternating (weak first).
  public func smartMix(
    count: Int, pool: DrillPool, skills: SkillModel, cards: [DecisionCardState], now: Date, seed: UInt64
  ) -> [DrillPick] {
    guard count > 0 else { return [] }
    var picks: [DrillPick] = []

    var skillOfTemplate: [String: String] = [:]
    for e in pool.entries.sorted(by: { ($0.order, $0.templateID) < ($1.order, $1.templateID) })
    where skillOfTemplate[e.templateID] == nil {
      skillOfTemplate[e.templateID] = e.skill
    }
    let due = cards.filter { $0.card.due <= now && skillOfTemplate[$0.key.templateID] != nil }
      .sorted { ($0.card.due, $0.key.rawValue) < ($1.card.due, $1.key.rawValue) }
    for c in due.prefix(count) {
      picks.append(
        DrillPick(
          templateID: c.key.templateID, targetAnswerClass: c.key.answerClass,
          skill: skillOfTemplate[c.key.templateID] ?? "", reason: .due(c.key)))
    }

    // Skills in pool order (lowest entry order, then name).
    var firstOrder: [String: Int] = [:]
    var byOrder: [String: [DrillPool.Entry]] = [:]
    for e in pool.entries {
      firstOrder[e.skill] = min(firstOrder[e.skill] ?? Int.max, e.order)
      byOrder[e.skill, default: []].append(e)
    }
    let poolSkills = firstOrder.keys.sorted { (firstOrder[$0] ?? 0, $0) < (firstOrder[$1] ?? 0, $1) }
    func base(_ s: String) -> Double { pool.baseDifficulty[s] ?? 0.5 }
    let weak = poolSkills.filter { skills.rating($0).evidence > 0 && !skills.isMastered($0, baseDifficulty: base($0)) }
      .enumerated()
      .sorted {
        (skills.meter($0.element, baseDifficulty: base($0.element)), $0.offset)
          < (skills.meter($1.element, baseDifficulty: base($1.element)), $1.offset)
      }
      .map(\.element)
    let fresh = poolSkills.filter { skills.rating($0).evidence == 0 }

    var wi = 0
    var ni = 0
    var slot = 0
    while picks.count < count && !(weak.isEmpty && fresh.isEmpty) {
      let wantWeak = slot % 2 == 0
      let useWeak = weak.isEmpty ? false : (fresh.isEmpty ? true : wantWeak)
      let skill: String
      if useWeak {
        skill = weak[wi % weak.count]
        wi += 1
      } else {
        skill = fresh[ni % fresh.count]
        ni += 1
      }
      slot += 1
      let entries = (byOrder[skill] ?? []).sorted { ($0.order, $0.templateID) < ($1.order, $1.templateID) }
      let idx = Int(StableSeed.mix(seed, UInt64(picks.count)) % UInt64(entries.count))
      picks.append(
        DrillPick(
          templateID: entries[idx].templateID, targetAnswerClass: nil, skill: skill,
          reason: useWeak ? .weakSkill(skill) : .newMaterial(skill)))
    }
    return picks
  }

  public func warmUp(
    pool: DrillPool, skills: SkillModel, cards: [DecisionCardState], now: Date, seed: UInt64
  ) -> [DrillPick] {
    smartMix(count: 10, pool: pool, skills: skills, cards: cards, now: now, seed: seed)
  }

  /// leak → again; smallMiss → hard; good → good; good && fast && !usedHint → easy.
  public static func rating(grade: Grade, fast: Bool, usedHint: Bool) -> FSRSRating {
    switch grade {
    case .leak: return .again
    case .smallMiss: return .hard
    case .good: return fast && !usedHint ? .easy : .good
    }
  }

  public func review(
    _ state: DecisionCardState?, key: DecisionTypeKey, grade: Grade, fast: Bool, usedHint: Bool,
    instanceHash: String, now: Date
  ) -> DecisionCardState {
    let cal = scheduler.calendar
    let card = state?.card ?? FSRSCard.new(now: now)
    let rating = Self.rating(grade: grade, fast: fast, usedHint: usedHint)
    let result = scheduler.next(card, rating: rating, now: now)
    let today = DayKey(now, calendar: cal)
    let cutoff = today.adding(days: -Self.noRepeatDays, calendar: cal)
    var recent = (state?.recent ?? []).filter { $0.day >= cutoff }
    recent.append(RecentInstance(hash: instanceHash, day: today))
    return DecisionCardState(key: key, card: result.card, recent: recent)
  }

  /// Instance hashes seen within the last `noRepeatDays` days.
  public static func avoidSet(
    _ cards: [DecisionCardState], now: Date, calendar: Calendar = DayKey.gregorian()
  ) -> Set<String> {
    let cutoff = DayKey(now, calendar: calendar).adding(days: -noRepeatDays, calendar: calendar)
    var out: Set<String> = []
    for c in cards {
      for r in c.recent where r.day >= cutoff { out.insert(r.hash) }
    }
    return out
  }
}
