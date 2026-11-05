import Foundation
import PokerCore

public struct SpotTableSpec: Codable, Sendable, Hashable {
  public let players: Int
  public let stacksBB: IntRangeSpec
  public let blinds: Blinds
  public let fillerNames: [String]?

  public init(players: Int, stacksBB: IntRangeSpec, blinds: Blinds, fillerNames: [String]? = nil) {
    self.players = players
    self.stacksBB = stacksBB
    self.blinds = blinds
    self.fillerNames = fillerNames
  }

  private enum CodingKeys: String, CodingKey { case players, stacksBB, blinds, fillerNames }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let players = try c.decode(Int.self, forKey: .players)
    guard (2...9).contains(players) else { throw corrupted(decoder, "players \(players) must be 2...9") }
    self.init(
      players: players, stacksBB: try c.decode(IntRangeSpec.self, forKey: .stacksBB),
      blinds: try c.decode(Blinds.self, forKey: .blinds),
      fillerNames: try c.decodeIfPresent([String].self, forKey: .fillerNames))
  }
}

/// `position` is written as one name or a list of names.
private func decodePositions<K: CodingKey>(
  _ c: KeyedDecodingContainer<K>, _ key: K
) throws -> [SeatPositionName]? {
  guard c.contains(key) else { return nil }
  if let one = try? c.decode(SeatPositionName.self, forKey: key) { return [one] }
  return try c.decode([SeatPositionName].self, forKey: key)
}

public struct HeroSpec: Codable, Sendable, Hashable {
  public let position: [SeatPositionName]?
  public let hand: HandPredicate?

  public init(position: [SeatPositionName]? = nil, hand: HandPredicate? = nil) {
    self.position = position
    self.hand = hand
  }

  private enum CodingKeys: String, CodingKey { case position, hand }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      position: try decodePositions(c, .position), hand: try c.decodeIfPresent(HandPredicate.self, forKey: .hand))
  }
}

public struct VillainSpec: Codable, Sendable, Hashable {
  public let characters: [String]
  public let names: [String]?
  public let position: [SeatPositionName]?
  public let hand: HandPredicate?

  public init(
    characters: [String] = [], names: [String]? = nil, position: [SeatPositionName]? = nil,
    hand: HandPredicate? = nil
  ) {
    self.characters = characters
    self.names = names
    self.position = position
    self.hand = hand
  }

  private enum CodingKeys: String, CodingKey { case character, characters, names, position, hand }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if c.contains(.character) && c.contains(.characters) {
      throw corrupted(decoder, "use either 'character' or 'characters', not both")
    }
    var characters: [String] = []
    if let one = try c.decodeIfPresent(String.self, forKey: .character) {
      characters = [one]
    } else if let many = try c.decodeIfPresent([String].self, forKey: .characters) {
      characters = many
    }
    self.init(
      characters: characters, names: try c.decodeIfPresent([String].self, forKey: .names),
      position: try decodePositions(c, .position), hand: try c.decodeIfPresent(HandPredicate.self, forKey: .hand))
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    if !characters.isEmpty { try c.encode(characters, forKey: .characters) }
    try c.encodeIfPresent(names, forKey: .names)
    try c.encodeIfPresent(position, forKey: .position)
    try c.encodeIfPresent(hand, forKey: .hand)
  }
}

public enum QuestionType: String, ContentEnum {
  case action, pickWinner, pickCards, pickHandClass, number, rangePaint, sizeChoice, choice
}

public struct QuestionSpec: Codable, Sendable, Hashable {
  public let type: QuestionType
  public let options: [String]?
  public let tolerance: Int?
  public let pick: Int?

  public init(type: QuestionType, options: [String]? = nil, tolerance: Int? = nil, pick: Int? = nil) {
    self.type = type
    self.options = options
    self.tolerance = tolerance
    self.pick = pick
  }
}

public enum EvaluationMethod: String, ContentEnum {
  case showdownWinner, bestFive, nuts, beatsMeCount, potCount, legalSizes, nextToAct, closedFormEV, policyEV
  case rangeMatch, pushFold, outs

  /// Methods graded by expected value.
  public var isEV: Bool { self == .closedFormEV || self == .policyEV || self == .pushFold }
}

public enum LegalAsk: String, ContentEnum { case callCost, minRaise, actions }

public struct CountBucket: Codable, Sendable, Hashable {
  public let id: String
  public let label: String
  public let range: IntRangeSpec

  public init(id: String, label: String, range: IntRangeSpec) {
    self.id = id
    self.label = label
    self.range = range
  }
}

public struct EvaluationSpec: Codable, Sendable, Hashable {
  public let method: EvaluationMethod
  public let ask: LegalAsk?
  public let buckets: [CountBucket]?
  /// "tracked" or range text.
  public let vsRange: String?
  /// "policy" or range text.
  public let target: String?
  public let equitySamples: Int?

  public init(
    method: EvaluationMethod, ask: LegalAsk? = nil, buckets: [CountBucket]? = nil, vsRange: String? = nil,
    target: String? = nil, equitySamples: Int? = nil
  ) {
    self.method = method
    self.ask = ask
    self.buckets = buckets
    self.vsRange = vsRange
    self.target = target
    self.equitySamples = equitySamples
  }
}

public struct QualitySpec: Codable, Sendable, Hashable {
  public let minGapBB: Double?
  public let answerBalance: [String: DoubleRangeSpec]
  public let maxRetries: Int

  public init(minGapBB: Double? = nil, answerBalance: [String: DoubleRangeSpec] = [:], maxRetries: Int = 4) {
    self.minGapBB = minGapBB
    self.answerBalance = answerBalance
    self.maxRetries = maxRetries
  }

  private enum CodingKeys: String, CodingKey { case minGapBB, answerBalance, maxRetries }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      minGapBB: try c.decodeIfPresent(Double.self, forKey: .minGapBB),
      answerBalance: try c.decodeIfPresent([String: DoubleRangeSpec].self, forKey: .answerBalance) ?? [:],
      maxRetries: try c.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 4)
  }
}

public enum VariationKind: String, ContentEnum { case suits, seats, stacks, villainName }

public enum RevealSpec: String, ContentEnum { case hero, all }

public struct SpotTemplate: Codable, Sendable, Hashable, Identifiable {
  public let schemaVersion: Int
  public let id: String
  public let skill: String
  public let difficulty: Double
  public let table: SpotTableSpec
  public let hero: HeroSpec
  public let villains: [VillainSpec]
  public let fixed: FixedCards?
  public let line: LineSpec
  public let board: BoardPredicate
  public let situation: SituationPredicate?
  public let potBB: DoubleRangeSpec?
  public let question: QuestionSpec
  public let evaluation: EvaluationSpec
  public let quality: QualitySpec
  public let prompt: String
  public let coach: String?
  public let hint: String?
  public let explain: [ExplainerRef]
  public let variation: Set<VariationKind>
  public let reveal: RevealSpec

  public init(
    schemaVersion: Int = ContentSchema.version, id: String, skill: String, difficulty: Double, table: SpotTableSpec,
    hero: HeroSpec = HeroSpec(), villains: [VillainSpec] = [], fixed: FixedCards? = nil,
    line: LineSpec = .checkThrough, board: BoardPredicate, situation: SituationPredicate? = nil,
    potBB: DoubleRangeSpec? = nil, question: QuestionSpec, evaluation: EvaluationSpec,
    quality: QualitySpec = QualitySpec(), prompt: String, coach: String? = nil, hint: String? = nil,
    explain: [ExplainerRef] = [], variation: Set<VariationKind> = [], reveal: RevealSpec = .hero
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.skill = skill
    self.difficulty = difficulty
    self.table = table
    self.hero = hero
    self.villains = villains
    self.fixed = fixed
    self.line = line
    self.board = board
    self.situation = situation
    self.potBB = potBB
    self.question = question
    self.evaluation = evaluation
    self.quality = quality
    self.prompt = prompt
    self.coach = coach
    self.hint = hint
    self.explain = explain
    self.variation = variation
    self.reveal = reveal
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, id, skill, difficulty, table, hero, villain, villains, fixed, line, board, situation, potBB
    case question, evaluation, quality, prompt, coach, hint, explain, variation, reveal
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if c.contains(.villain) && c.contains(.villains) {
      throw corrupted(decoder, "use either 'villain' or 'villains', not both")
    }
    var villains: [VillainSpec] = []
    if let one = try c.decodeIfPresent(VillainSpec.self, forKey: .villain) {
      villains = [one]
    } else if let many = try c.decodeIfPresent([VillainSpec].self, forKey: .villains) {
      villains = many
    }
    let difficulty = try c.decode(Double.self, forKey: .difficulty)
    guard (0...1).contains(difficulty) else {
      throw DecodingError.dataCorruptedError(
        forKey: .difficulty, in: c, debugDescription: "difficulty \(formatNumber(difficulty)) must be 0...1")
    }
    self.init(
      schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), id: try c.decode(String.self, forKey: .id),
      skill: try c.decode(String.self, forKey: .skill), difficulty: difficulty,
      table: try c.decode(SpotTableSpec.self, forKey: .table),
      hero: try c.decodeIfPresent(HeroSpec.self, forKey: .hero) ?? HeroSpec(), villains: villains,
      fixed: try c.decodeIfPresent(FixedCards.self, forKey: .fixed),
      line: try c.decodeIfPresent(LineSpec.self, forKey: .line) ?? .checkThrough,
      board: try c.decode(BoardPredicate.self, forKey: .board),
      situation: try c.decodeIfPresent(SituationPredicate.self, forKey: .situation),
      potBB: try c.decodeIfPresent(DoubleRangeSpec.self, forKey: .potBB),
      question: try c.decode(QuestionSpec.self, forKey: .question),
      evaluation: try c.decode(EvaluationSpec.self, forKey: .evaluation),
      quality: try c.decodeIfPresent(QualitySpec.self, forKey: .quality) ?? QualitySpec(),
      prompt: try c.decode(String.self, forKey: .prompt), coach: try c.decodeIfPresent(String.self, forKey: .coach),
      hint: try c.decodeIfPresent(String.self, forKey: .hint),
      explain: try c.decodeIfPresent([ExplainerRef].self, forKey: .explain) ?? [],
      variation: Set(try c.decodeIfPresent([VariationKind].self, forKey: .variation) ?? []),
      reveal: try c.decodeIfPresent(RevealSpec.self, forKey: .reveal) ?? .hero)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(schemaVersion, forKey: .schemaVersion)
    try c.encode(id, forKey: .id)
    try c.encode(skill, forKey: .skill)
    try c.encode(difficulty, forKey: .difficulty)
    try c.encode(table, forKey: .table)
    try c.encode(hero, forKey: .hero)
    if !villains.isEmpty { try c.encode(villains, forKey: .villains) }
    try c.encodeIfPresent(fixed, forKey: .fixed)
    try c.encode(line, forKey: .line)
    try c.encode(board, forKey: .board)
    try c.encodeIfPresent(situation, forKey: .situation)
    try c.encodeIfPresent(potBB, forKey: .potBB)
    try c.encode(question, forKey: .question)
    try c.encode(evaluation, forKey: .evaluation)
    try c.encode(quality, forKey: .quality)
    try c.encode(prompt, forKey: .prompt)
    try c.encodeIfPresent(coach, forKey: .coach)
    try c.encodeIfPresent(hint, forKey: .hint)
    try c.encode(explain, forKey: .explain)
    try c.encode(variation.map(\.rawValue).sorted(), forKey: .variation)
    try c.encode(reveal, forKey: .reveal)
  }
}

public struct CharacterInfo: Decodable, Sendable, Hashable {
  public let id: String
  public let name: String
  public let style: String
  public let title: String?
  public let artKey: String?
  public let bio: String?
  public let quote: String?
  public let howToBeat: String?
  public let names: [String]?

  public init(
    id: String, name: String, style: String = "", title: String? = nil, artKey: String? = nil, bio: String? = nil,
    quote: String? = nil, howToBeat: String? = nil, names: [String]? = nil
  ) {
    self.id = id
    self.name = name
    self.style = style
    self.title = title
    self.artKey = artKey
    self.bio = bio
    self.quote = quote
    self.howToBeat = howToBeat
    self.names = names
  }

  private enum CodingKeys: String, CodingKey { case id, name, style, title, artKey, bio, quote, howToBeat, names }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try c.decode(String.self, forKey: .id), name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
      style: try c.decodeIfPresent(String.self, forKey: .style) ?? "",
      title: try c.decodeIfPresent(String.self, forKey: .title),
      artKey: try c.decodeIfPresent(String.self, forKey: .artKey),
      bio: try c.decodeIfPresent(String.self, forKey: .bio),
      quote: try c.decodeIfPresent(String.self, forKey: .quote),
      howToBeat: try c.decodeIfPresent(String.self, forKey: .howToBeat),
      names: try c.decodeIfPresent([String].self, forKey: .names))
  }
}
