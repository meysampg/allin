import Foundation
import PokerCore
import PokerEquity

/// Constraints on a dealt hand. Every key is optional; all given keys must hold.
public struct HandPredicate: Codable, Sendable, Hashable {
  public let madeHand: [MadeHandName]?
  public let bucket: [StrengthBucket]?
  public let draws: [DrawName]?
  public let categories: [HandCategoryName]?
  public let range: RangeSpec?
  public let pocketPair: Bool?
  public let suited: Bool?
  public let outs: IntRangeSpec?

  public init(
    madeHand: [MadeHandName]? = nil, bucket: [StrengthBucket]? = nil, draws: [DrawName]? = nil,
    categories: [HandCategoryName]? = nil, range: RangeSpec? = nil, pocketPair: Bool? = nil, suited: Bool? = nil,
    outs: IntRangeSpec? = nil
  ) {
    self.madeHand = madeHand
    self.bucket = bucket
    self.draws = draws
    self.categories = categories
    self.range = range
    self.pocketPair = pocketPair
    self.suited = suited
    self.outs = outs
  }
}

/// The board of a spot: its street and texture constraints.
public struct BoardPredicate: Codable, Sendable, Hashable {
  public let street: Street
  public let require: [TextureTag]
  public let exclude: [TextureTag]
  public let highCard: [Rank]?

  public init(street: Street, require: [TextureTag] = [], exclude: [TextureTag] = [], highCard: [Rank]? = nil) {
    self.street = street
    self.require = require
    self.exclude = exclude
    self.highCard = highCard
  }

  private enum CodingKeys: String, CodingKey { case street, require, exclude, highCard }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    var ranks: [Rank]?
    if c.contains(.highCard) {
      var list = try c.nestedUnkeyedContainer(forKey: .highCard)
      var parsed: [Rank] = []
      while !list.isAtEnd {
        let symbol = try list.decode(String.self)
        guard symbol.count == 1, let rank = Rank(symbol: symbol.first!) else {
          throw DecodingError.dataCorrupted(
            DecodingError.Context(
              codingPath: list.codingPath + [IndexKey(list.currentIndex - 1)],
              debugDescription: "unknown rank '\(symbol)' (expected 2-9|T|J|Q|K|A)"))
        }
        parsed.append(rank)
      }
      ranks = parsed
    }
    self.init(
      street: try c.decode(Street.self, forKey: .street),
      require: try c.decodeIfPresent([TextureTag].self, forKey: .require) ?? [],
      exclude: try c.decodeIfPresent([TextureTag].self, forKey: .exclude) ?? [], highCard: ranks)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(street, forKey: .street)
    try c.encode(require, forKey: .require)
    try c.encode(exclude, forKey: .exclude)
    try c.encodeIfPresent(highCard?.map { String($0.symbol) }, forKey: .highCard)
  }
}

struct IndexKey: CodingKey {
  var stringValue: String { "\(intValue ?? 0)" }
  var intValue: Int?

  init(_ index: Int) { intValue = index }
  init?(stringValue: String) { nil }
  init?(intValue: Int) { self.intValue = intValue }
}

public struct SituationPredicate: Codable, Sendable, Hashable {
  public let facingBet: Bool?
  public let heroInPosition: Bool?
  public let spr: DoubleRangeSpec?

  public init(facingBet: Bool? = nil, heroInPosition: Bool? = nil, spr: DoubleRangeSpec? = nil) {
    self.facingBet = facingBet
    self.heroInPosition = heroInPosition
    self.spr = spr
  }
}

/// Cards fixed by the author, written as card strings ("AhKh", "Ks9h4h").
public struct FixedCards: Codable, Sendable, Hashable {
  public let hero: [Card]?
  public let villains: [[Card]]?
  public let board: [Card]?

  public init(hero: [Card]? = nil, villains: [[Card]]? = nil, board: [Card]? = nil) {
    self.hero = hero
    self.villains = villains
    self.board = board
  }

  private enum CodingKeys: String, CodingKey { case hero, villains, board }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func cards(_ key: CodingKeys) throws -> [Card]? {
      guard let text = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
      do { return try Card.parseList(text) } catch {
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "bad cards '\(text)' (\(error))")
      }
    }
    var villains: [[Card]]?
    if let texts = try c.decodeIfPresent([String].self, forKey: .villains) {
      villains = try texts.enumerated().map { index, text in
        do { return try Card.parseList(text) } catch {
          throw DecodingError.dataCorrupted(
            DecodingError.Context(
              codingPath: c.codingPath + [CodingKeys.villains, IndexKey(index)],
              debugDescription: "bad cards '\(text)' (\(error))"))
        }
      }
    }
    self.init(hero: try cards(.hero), villains: villains, board: try cards(.board))
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(hero.map(Card.format), forKey: .hero)
    try c.encodeIfPresent(villains?.map(Card.format), forKey: .villains)
    try c.encodeIfPresent(board.map(Card.format), forKey: .board)
  }
}

public enum LineRole: String, ContentEnum { case hero, villain, villain2, villain3 }

public enum LineAct: Hashable, Sendable {
  case fold, check, call, limp, allIn, any
  case bet(DoubleRangeSpec)
  case raise(Double)
  case open(Double)
}

/// `[role:]act`, for example `villain:bet:0.5-0.75`, `hero:call`, `raise:3`.
public struct LineToken: Codable, Sendable, Hashable, CustomStringConvertible {
  public let role: LineRole?
  public let act: LineAct

  public init(role: LineRole? = nil, act: LineAct) {
    self.role = role
    self.act = act
  }

  static let actHelp = "fold|check|call|limp|allin|any|bet:F|bet:F-G|raise:X|open:B"

  /// Parses a token, throwing a readable message.
  public init(parsing text: String) throws {
    var parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    var role: LineRole?
    if parts.count > 1, let found = LineRole(rawValue: parts[0]) {
      role = found
      parts.removeFirst()
    }
    func bad(_ expected: String) -> LineTokenError { LineTokenError(text: text, expected: expected) }
    let argument = parts.dropFirst().joined(separator: ":")
    let act: LineAct
    switch parts.first ?? "" {
    case "fold", "check", "call", "limp", "allin", "any":
      guard parts.count == 1 else { throw bad(parts[0]) }
      let simple: [String: LineAct] = [
        "fold": .fold, "check": .check, "call": .call, "limp": .limp, "allin": .allIn, "any": .any,
      ]
      act = simple[parts[0]]!
    case "bet":
      let bounds = argument.split(separator: "-", omittingEmptySubsequences: false).map { Double($0) }
      guard (1...2).contains(bounds.count), bounds.allSatisfy({ $0 != nil && $0! > 0 && $0! <= 3 }),
        bounds.count == 1 || bounds[0]! <= bounds[1]!
      else { throw bad("bet:<fraction>") }
      act = .bet(DoubleRangeSpec(lo: bounds[0]!, hi: bounds.last!!))
    case "raise":
      guard parts.count == 2, let x = Double(argument), x >= 2 else { throw bad("raise:<multiple of at least 2>") }
      act = .raise(x)
    case "open":
      guard parts.count == 2, let b = Double(argument), b >= 2 else { throw bad("open:<big blinds, at least 2>") }
      act = .open(b)
    default:
      throw bad(LineToken.actHelp)
    }
    self.init(role: role, act: act)
  }

  public var description: String {
    let prefix = role.map { "\($0.rawValue):" } ?? ""
    switch act {
    case .fold: return prefix + "fold"
    case .check: return prefix + "check"
    case .call: return prefix + "call"
    case .limp: return prefix + "limp"
    case .allIn: return prefix + "allin"
    case .any: return prefix + "any"
    case .bet(let size):
      let range =
        size.lo == size.hi ? formatNumber(size.lo) : "\(formatNumber(size.lo))-\(formatNumber(size.hi))"
      return prefix + "bet:" + range
    case .raise(let x): return prefix + "raise:" + formatNumber(x)
    case .open(let b): return prefix + "open:" + formatNumber(b)
    }
  }

  private enum ObjectKeys: String, CodingKey { case role, act }

  public init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
      do { self = try LineToken(parsing: text) } catch { throw corrupted(decoder, "\(error)") }
      return
    }
    let c = try decoder.container(keyedBy: ObjectKeys.self)
    let role = try c.decodeIfPresent(LineRole.self, forKey: .role)
    let text = try c.decode(String.self, forKey: .act)
    do {
      let parsed = try LineToken(parsing: text)
      guard parsed.role == nil else { throw LineTokenError(text: text, expected: "an act without a role prefix") }
      self.init(role: role, act: parsed.act)
    } catch { throw corrupted(decoder, "\(error)") }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

struct LineTokenError: Error, CustomStringConvertible {
  let text: String
  let expected: String

  var description: String { "bad line token '\(text)' (expected \(expected))" }
}

public enum LineStop: String, ContentEnum { case hero, villain, any }

public struct RandomLineSpec: Codable, Sendable, Hashable {
  public let actions: IntRangeSpec

  public init(actions: IntRangeSpec) { self.actions = actions }
}

/// The action line leading to the decision: a preset string or an object.
public struct LineSpec: Codable, Sendable, Hashable {
  public let streets: [Street: [LineToken]]
  public let random: RandomLineSpec?
  public let stopAt: LineStop
  public let consistent: Bool

  public init(
    streets: [Street: [LineToken]] = [:], random: RandomLineSpec? = nil, stopAt: LineStop = .hero,
    consistent: Bool = true
  ) {
    self.streets = streets
    self.random = random
    self.stopAt = stopAt
    self.consistent = consistent
  }

  /// JSON `"checkThrough"`.
  public static let checkThrough = LineSpec()

  private enum CodingKeys: String, CodingKey { case preflop, flop, turn, river, random, stopAt, consistent }

  public init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
      guard text == "checkThrough" else {
        throw corrupted(decoder, "unknown value '\(text)' (expected checkThrough)")
      }
      self = .checkThrough
      return
    }
    let c = try decoder.container(keyedBy: CodingKeys.self)
    var streets: [Street: [LineToken]] = [:]
    for (street, key) in [(Street.preflop, CodingKeys.preflop), (.flop, .flop), (.turn, .turn), (.river, .river)] {
      if let tokens = try c.decodeIfPresent([LineToken].self, forKey: key) { streets[street] = tokens }
    }
    self.init(
      streets: streets, random: try c.decodeIfPresent(RandomLineSpec.self, forKey: .random),
      stopAt: try c.decodeIfPresent(LineStop.self, forKey: .stopAt) ?? .hero,
      consistent: try c.decodeIfPresent(Bool.self, forKey: .consistent) ?? true)
  }

  public func encode(to encoder: Encoder) throws {
    if self == .checkThrough {
      var container = encoder.singleValueContainer()
      try container.encode("checkThrough")
      return
    }
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(streets[.preflop], forKey: .preflop)
    try c.encodeIfPresent(streets[.flop], forKey: .flop)
    try c.encodeIfPresent(streets[.turn], forKey: .turn)
    try c.encodeIfPresent(streets[.river], forKey: .river)
    try c.encodeIfPresent(random, forKey: .random)
    try c.encode(stopAt, forKey: .stopAt)
    try c.encode(consistent, forKey: .consistent)
  }
}
