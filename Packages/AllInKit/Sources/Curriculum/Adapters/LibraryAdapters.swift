import Foundation

extension ContentLibrary {
  /// Templates the unlocked venues play, in venue and node order, deduplicated by template.
  /// Lessons contribute their hook, puzzle and apply spots, drills their spots and bosses their exam draws.
  public func drillPool(unlockedVenues: [String]) -> DrillPool {
    var entries: [DrillPool.Entry] = []
    var seen: Set<String> = []
    func add(_ templateID: String) {
      guard !seen.contains(templateID), let template = templates[templateID] else { return }
      seen.insert(templateID)
      entries.append(DrillPool.Entry(templateID: templateID, skill: template.skill, order: entries.count))
    }
    for venueID in unlockedVenues {
      guard let venue = venue(venueID) else { continue }
      for node in venue.nodes {
        if let id = node.lesson, let lesson = lessons[id] {
          for step in lesson.steps { if let spot = step.spotID { add(spot) } }
        }
        if let id = node.drill, let drill = drills[id] {
          for spot in drill.spots { add(spot.template) }
        }
        if let id = node.boss, let boss = bosses[id], let exam = exams[boss.exam] {
          for draw in exam.draw { add(draw.template) }
        }
      }
    }
    return DrillPool(entries: entries, baseDifficulty: skills.baseDifficulties)
  }

  /// The mean meter of the venue meter's skills.
  public func meterValue(_ meter: VenueMeter, skills model: SkillModel) -> Double {
    model.groupMeter(meter.skills, baseDifficulty: skills.baseDifficulties)
  }
}

extension DecisionCardState {
  /// Rebuilds a card from its stored fields. Nil when the key is not `"<template>#<class>"`.
  /// Instance hashes that do not parse are dropped.
  public init?(
    stored key: String, stateRaw: Int, stability: Double, difficulty: Double, due: Date, lastReview: Date?,
    reps: Int, lapses: Int, instanceHashes: [String]
  ) {
    guard let key = DecisionTypeKey(rawValue: key) else { return nil }
    let card = FSRSCard(
      stability: stability, difficulty: difficulty, due: due, lastReview: lastReview, reps: reps, lapses: lapses,
      state: FSRSCardState(rawValue: stateRaw) ?? .new)
    self.init(key: key, card: card, recent: instanceHashes.compactMap { RecentInstance(rawValue: $0) })
  }

  /// The recent instances as stored strings (`"<hash>|<yyyy-MM-dd>"`).
  public var instanceHashStrings: [String] { recent.map(\.rawValue) }
}
