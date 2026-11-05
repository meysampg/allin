import Foundation

public enum ExplainerKind: String, ContentEnum {
  case bettingRoundsTimeline, handRankLadder, bestFiveHighlight, potCounter, boardNutsScan, whoCallsMe, potSlices,
    outsGlow

  /// Allowed `bind` keys.
  public var bindKeys: Set<String> {
    switch self {
    case .handRankLadder: ["highlight"]
    case .bestFiveHighlight: ["hand"]
    case .whoCallsMe: ["range", "hand", "mode", "size"]
    default: []
    }
  }
}

/// JSON `"potSlices"` or `{ "explainer": "potSlices", "bind": {...}, "caption": "..." }`.
public struct ExplainerRef: Codable, Sendable, Hashable {
  public let explainer: ExplainerKind
  public let bind: [String: String]
  public let caption: String?

  public init(explainer: ExplainerKind, bind: [String: String] = [:], caption: String? = nil) {
    self.explainer = explainer
    self.bind = bind
    self.caption = caption
  }

  private enum CodingKeys: String, CodingKey { case explainer, bind, caption }

  public init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
      guard let kind = ExplainerKind(rawValue: text) else {
        let all = ExplainerKind.allCases.map(\.rawValue).joined(separator: "|")
        throw corrupted(decoder, "unknown value '\(text)' (expected \(all))")
      }
      self.init(explainer: kind)
      return
    }
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      explainer: try c.decode(ExplainerKind.self, forKey: .explainer),
      bind: try c.decodeIfPresent([String: String].self, forKey: .bind) ?? [:],
      caption: try c.decodeIfPresent(String.self, forKey: .caption))
  }
}

public enum SandboxControl: String, ContentEnum { case heroCards, board, villainBet }

public enum SandboxMeter: String, ContentEnum {
  case priceNeeded, yourChance, worseThatCall, betterThatCall, potAfter, outs, bestFive, nuts
}

public enum LessonStepKind: String, ContentEnum { case hook, puzzle, explain, sandbox, apply }

/// Keys shared by every step payload (the step is tagged by "kind").
enum StepKeys: String, CodingKey {
  case kind, spot, coach, hint, title, explainers, thinking, controls, meters, explainer, challenge, count,
    freshSeeds
}

public struct SpotStep: Codable, Sendable, Hashable {
  public let spot: String
  public let coach: String?
  public let hint: String?

  public init(spot: String, coach: String? = nil, hint: String? = nil) {
    self.spot = spot
    self.coach = coach
    self.hint = hint
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: StepKeys.self)
    self.init(
      spot: try c.decode(String.self, forKey: .spot), coach: try c.decodeIfPresent(String.self, forKey: .coach),
      hint: try c.decodeIfPresent(String.self, forKey: .hint))
  }

  func encodeFields(_ c: inout KeyedEncodingContainer<StepKeys>) throws {
    try c.encode(spot, forKey: .spot)
    try c.encodeIfPresent(coach, forKey: .coach)
    try c.encodeIfPresent(hint, forKey: .hint)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: StepKeys.self)
    try encodeFields(&c)
  }
}

public struct ExplainStep: Codable, Sendable, Hashable {
  public let title: String?
  public let explainers: [ExplainerRef]
  public let thinking: String?

  public init(title: String? = nil, explainers: [ExplainerRef], thinking: String? = nil) {
    self.title = title
    self.explainers = explainers
    self.thinking = thinking
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: StepKeys.self)
    self.init(
      title: try c.decodeIfPresent(String.self, forKey: .title),
      explainers: try c.decode([ExplainerRef].self, forKey: .explainers),
      thinking: try c.decodeIfPresent(String.self, forKey: .thinking))
  }

  func encodeFields(_ c: inout KeyedEncodingContainer<StepKeys>) throws {
    try c.encodeIfPresent(title, forKey: .title)
    try c.encode(explainers, forKey: .explainers)
    try c.encodeIfPresent(thinking, forKey: .thinking)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: StepKeys.self)
    try encodeFields(&c)
  }
}

public struct SandboxStep: Codable, Sendable, Hashable {
  public let title: String?
  public let controls: [SandboxControl]
  public let meters: [SandboxMeter]
  public let explainer: ExplainerKind?
  public let challenge: String?

  public init(
    title: String? = nil, controls: [SandboxControl], meters: [SandboxMeter], explainer: ExplainerKind? = nil,
    challenge: String? = nil
  ) {
    self.title = title
    self.controls = controls
    self.meters = meters
    self.explainer = explainer
    self.challenge = challenge
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: StepKeys.self)
    self.init(
      title: try c.decodeIfPresent(String.self, forKey: .title),
      controls: try c.decode([SandboxControl].self, forKey: .controls),
      meters: try c.decode([SandboxMeter].self, forKey: .meters),
      explainer: try c.decodeIfPresent(ExplainerKind.self, forKey: .explainer),
      challenge: try c.decodeIfPresent(String.self, forKey: .challenge))
  }

  func encodeFields(_ c: inout KeyedEncodingContainer<StepKeys>) throws {
    try c.encodeIfPresent(title, forKey: .title)
    try c.encode(controls, forKey: .controls)
    try c.encode(meters, forKey: .meters)
    try c.encodeIfPresent(explainer, forKey: .explainer)
    try c.encodeIfPresent(challenge, forKey: .challenge)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: StepKeys.self)
    try encodeFields(&c)
  }
}

public struct ApplyStep: Codable, Sendable, Hashable {
  public let spot: String
  public let count: Int
  public let freshSeeds: Bool
  public let coach: String?

  public init(spot: String, count: Int, freshSeeds: Bool = true, coach: String? = nil) {
    self.spot = spot
    self.count = count
    self.freshSeeds = freshSeeds
    self.coach = coach
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: StepKeys.self)
    let count = try c.decode(Int.self, forKey: .count)
    guard (1...10).contains(count) else { throw corrupted(decoder, "apply count \(count) must be 1...10") }
    self.init(
      spot: try c.decode(String.self, forKey: .spot), count: count,
      freshSeeds: try c.decodeIfPresent(Bool.self, forKey: .freshSeeds) ?? true,
      coach: try c.decodeIfPresent(String.self, forKey: .coach))
  }

  func encodeFields(_ c: inout KeyedEncodingContainer<StepKeys>) throws {
    try c.encode(spot, forKey: .spot)
    try c.encode(count, forKey: .count)
    try c.encode(freshSeeds, forKey: .freshSeeds)
    try c.encodeIfPresent(coach, forKey: .coach)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: StepKeys.self)
    try encodeFields(&c)
  }
}

public enum LessonStep: Codable, Sendable, Hashable {
  case hook(SpotStep)
  case puzzle(SpotStep)
  case explain(ExplainStep)
  case sandbox(SandboxStep)
  case apply(ApplyStep)

  public var kind: LessonStepKind {
    switch self {
    case .hook: .hook
    case .puzzle: .puzzle
    case .explain: .explain
    case .sandbox: .sandbox
    case .apply: .apply
    }
  }

  /// The template a hook, puzzle or apply step plays.
  public var spotID: String? {
    switch self {
    case .hook(let step), .puzzle(let step): step.spot
    case .apply(let step): step.spot
    case .explain, .sandbox: nil
    }
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: StepKeys.self)
    switch try c.decode(LessonStepKind.self, forKey: .kind) {
    case .hook: self = .hook(try SpotStep(from: decoder))
    case .puzzle: self = .puzzle(try SpotStep(from: decoder))
    case .explain: self = .explain(try ExplainStep(from: decoder))
    case .sandbox: self = .sandbox(try SandboxStep(from: decoder))
    case .apply: self = .apply(try ApplyStep(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: StepKeys.self)
    try c.encode(kind, forKey: .kind)
    switch self {
    case .hook(let step), .puzzle(let step): try step.encodeFields(&c)
    case .explain(let step): try step.encodeFields(&c)
    case .sandbox(let step): try step.encodeFields(&c)
    case .apply(let step): try step.encodeFields(&c)
    }
  }
}

public struct StarRule: Codable, Sendable, Hashable {
  public let puzzleGood: Bool?
  public let applyGood: Int?

  public init(puzzleGood: Bool? = nil, applyGood: Int? = nil) {
    self.puzzleGood = puzzleGood
    self.applyGood = applyGood
  }
}

public struct LessonStars: Codable, Sendable, Hashable {
  public let hintCost: Int
  public let three: StarRule
  public let two: StarRule

  public init(
    hintCost: Int = 1, three: StarRule = StarRule(puzzleGood: true, applyGood: 3),
    two: StarRule = StarRule(applyGood: 2)
  ) {
    self.hintCost = hintCost
    self.three = three
    self.two = two
  }

  private enum CodingKeys: String, CodingKey { case hintCost, three, two }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      hintCost: try c.decodeIfPresent(Int.self, forKey: .hintCost) ?? 1,
      three: try c.decodeIfPresent(StarRule.self, forKey: .three) ?? StarRule(puzzleGood: true, applyGood: 3),
      two: try c.decodeIfPresent(StarRule.self, forKey: .two) ?? StarRule(applyGood: 2))
  }
}

public struct Lesson: Codable, Sendable, Hashable, Identifiable {
  public let schemaVersion: Int
  public let id: String
  public let title: String
  public let skills: [String]
  public let steps: [LessonStep]
  public let stars: LessonStars

  public init(
    schemaVersion: Int = ContentSchema.version, id: String, title: String, skills: [String], steps: [LessonStep],
    stars: LessonStars = LessonStars()
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.title = title
    self.skills = skills
    self.steps = steps
    self.stars = stars
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, id, title, skills, steps, stars }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), id: try c.decode(String.self, forKey: .id),
      title: try c.decode(String.self, forKey: .title),
      skills: try c.decodeIfPresent([String].self, forKey: .skills) ?? [],
      steps: try c.decode([LessonStep].self, forKey: .steps),
      stars: try c.decodeIfPresent(LessonStars.self, forKey: .stars) ?? LessonStars())
  }
}

public struct WeightedSpot: Codable, Sendable, Hashable {
  public let template: String
  public let weight: Double

  public init(template: String, weight: Double = 1) {
    self.template = template
    self.weight = weight
  }

  private enum CodingKeys: String, CodingKey { case template, weight }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      template: try c.decode(String.self, forKey: .template),
      weight: try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1)
  }
}

public struct Drill: Codable, Sendable, Hashable, Identifiable {
  public let schemaVersion: Int
  public let id: String
  public let title: String
  public let skills: [String]
  public let spots: [WeightedSpot]
  public let reps: Int
  public let timerSeconds: Int?
  public let gym: Bool

  public init(
    schemaVersion: Int = ContentSchema.version, id: String, title: String, skills: [String],
    spots: [WeightedSpot], reps: Int, timerSeconds: Int? = nil, gym: Bool = true
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.title = title
    self.skills = skills
    self.spots = spots
    self.reps = reps
    self.timerSeconds = timerSeconds
    self.gym = gym
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, id, title, skills, spots, reps, timerSeconds, gym
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), id: try c.decode(String.self, forKey: .id),
      title: try c.decode(String.self, forKey: .title),
      skills: try c.decodeIfPresent([String].self, forKey: .skills) ?? [],
      spots: try c.decode([WeightedSpot].self, forKey: .spots), reps: try c.decode(Int.self, forKey: .reps),
      timerSeconds: try c.decodeIfPresent(Int.self, forKey: .timerSeconds),
      gym: try c.decodeIfPresent(Bool.self, forKey: .gym) ?? true)
  }
}

public struct BossStarRule: Codable, Sendable, Hashable {
  public let score: Double
  public let exam: Int

  public init(score: Double, exam: Int) {
    self.score = score
    self.exam = exam
  }
}

public struct BossStars: Codable, Sendable, Hashable {
  public let two: BossStarRule
  public let three: BossStarRule

  public init(two: BossStarRule, three: BossStarRule) {
    self.two = two
    self.three = three
  }
}

public struct BossSpec: Codable, Sendable, Hashable, Identifiable {
  public let schemaVersion: Int
  public let id: String
  public let character: String
  public let title: String
  public let quote: String
  public let format: TableFormat
  public let hands: Int
  public let blinds: Blinds
  public let stackBB: Int
  public let coach: Bool
  public let minDecisions: Int
  public let minScore: Double
  public let requirements: [String]
  public let exam: String
  public let stars: BossStars

  public init(
    schemaVersion: Int = ContentSchema.version, id: String, character: String, title: String, quote: String = "",
    format: TableFormat, hands: Int, blinds: Blinds, stackBB: Int, coach: Bool = false, minDecisions: Int = 0,
    minScore: Double = 0, requirements: [String] = [], exam: String, stars: BossStars
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.character = character
    self.title = title
    self.quote = quote
    self.format = format
    self.hands = hands
    self.blinds = blinds
    self.stackBB = stackBB
    self.coach = coach
    self.minDecisions = minDecisions
    self.minScore = minScore
    self.requirements = requirements
    self.exam = exam
    self.stars = stars
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, id, character, title, quote, format, hands, blinds, stackBB, coach, minDecisions, minScore,
      requirements, exam, stars
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), id: try c.decode(String.self, forKey: .id),
      character: try c.decode(String.self, forKey: .character), title: try c.decode(String.self, forKey: .title),
      quote: try c.decodeIfPresent(String.self, forKey: .quote) ?? "",
      format: try c.decode(TableFormat.self, forKey: .format), hands: try c.decode(Int.self, forKey: .hands),
      blinds: try c.decode(Blinds.self, forKey: .blinds), stackBB: try c.decode(Int.self, forKey: .stackBB),
      coach: try c.decodeIfPresent(Bool.self, forKey: .coach) ?? false,
      minDecisions: try c.decodeIfPresent(Int.self, forKey: .minDecisions) ?? 0,
      minScore: try c.decodeIfPresent(Double.self, forKey: .minScore) ?? 0,
      requirements: try c.decodeIfPresent([String].self, forKey: .requirements) ?? [],
      exam: try c.decode(String.self, forKey: .exam), stars: try c.decode(BossStars.self, forKey: .stars))
  }
}

public struct ExamDraw: Codable, Sendable, Hashable {
  public let template: String
  public let count: Int

  public init(template: String, count: Int) {
    self.template = template
    self.count = count
  }
}

public struct ExamSpec: Codable, Sendable, Hashable, Identifiable {
  public let schemaVersion: Int
  public let id: String
  public let title: String
  public let count: Int
  public let pass: Int
  public let draw: [ExamDraw]

  public init(
    schemaVersion: Int = ContentSchema.version, id: String, title: String, count: Int, pass: Int, draw: [ExamDraw]
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.title = title
    self.count = count
    self.pass = pass
    self.draw = draw
  }
}
