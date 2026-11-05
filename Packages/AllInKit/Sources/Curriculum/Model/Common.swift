import Foundation
import PokerCore
import PokerEquity

public enum ContentSchema {
  public static let version = 1
}

/// A string-backed enum of the content format. Decoding reports `unknown value 'x' (expected a|b|c)`.
public protocol ContentEnum: RawRepresentable, CaseIterable, Codable, Sendable, Hashable where RawValue == String {}

extension ContentEnum {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    guard let value = Self(rawValue: raw) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "unknown value '\(raw)' (expected \(Self.allCases.map(\.rawValue).joined(separator: "|")))")
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Shortest text of a number: `2` for 2.0, `0.5` for 0.5.
func formatNumber(_ value: Double) -> String {
  if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
  return "\(value)"
}

func corrupted(_ decoder: Decoder, _ message: String) -> DecodingError {
  DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: message))
}

/// "S/B" or "S/B/A", in chips.
public struct Blinds: Codable, Sendable, Hashable, CustomStringConvertible {
  public let small: Int
  public let big: Int
  public let ante: Int

  public init(small: Int, big: Int, ante: Int = 0) {
    self.small = small
    self.big = big
    self.ante = ante
  }

  public var description: String { ante == 0 ? "\(small)/\(big)" : "\(small)/\(big)/\(ante)" }

  public init(from decoder: Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    let parts = text.split(separator: "/", omittingEmptySubsequences: false).map { Int($0) }
    guard parts.count == 2 || parts.count == 3, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else {
      throw corrupted(decoder, "bad blinds '\(text)' (expected S/B or S/B/ante)")
    }
    let values = parts.map { $0! }
    guard values[0] > 0, values[1] >= values[0] else {
      throw corrupted(decoder, "bad blinds '\(text)' (the big blind must be at least the small blind)")
    }
    self.init(small: values[0], big: values[1], ante: values.count == 3 ? values[2] : 0)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

/// JSON `[lo, hi]` or a single number `n` (meaning `[n, n]`).
public struct IntRangeSpec: Codable, Sendable, Hashable {
  public let lo: Int
  public let hi: Int

  public init(lo: Int, hi: Int) {
    self.lo = lo
    self.hi = hi
  }

  public var range: ClosedRange<Int> { lo...hi }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let single = try? container.decode(Int.self) {
      self.init(lo: single, hi: single)
      return
    }
    let pair = try container.decode([Int].self)
    guard pair.count == 2, pair[0] <= pair[1] else {
      throw corrupted(decoder, "expected a number or [lo,hi] with lo <= hi")
    }
    self.init(lo: pair[0], hi: pair[1])
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode([lo, hi])
  }
}

/// JSON `[lo, hi]` or a single number `x` (meaning `[x, x]`).
public struct DoubleRangeSpec: Codable, Sendable, Hashable {
  public let lo: Double
  public let hi: Double

  public init(lo: Double, hi: Double) {
    self.lo = lo
    self.hi = hi
  }

  public var range: ClosedRange<Double> { lo...hi }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let single = try? container.decode(Double.self) {
      self.init(lo: single, hi: single)
      return
    }
    let pair = try container.decode([Double].self)
    guard pair.count == 2, pair[0] <= pair[1] else {
      throw corrupted(decoder, "expected a number or [lo,hi] with lo <= hi")
    }
    self.init(lo: pair[0], hi: pair[1])
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode([lo, hi])
  }
}

/// A range written as text (`"22+, A2s+"`), parsed with `HandRange(parsing:)`. `HandRange` is not Codable.
public struct RangeSpec: Codable, Sendable, Hashable {
  public let text: String
  public let range: HandRange

  public init(text: String) throws {
    self.text = text
    self.range = try HandRange(parsing: text)
  }

  public init(from decoder: Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    do {
      try self.init(text: text)
    } catch {
      throw corrupted(decoder, "bad range '\(text)' (\(error))")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(text)
  }
}

public enum SeatPositionName: String, ContentEnum {
  case btn = "BTN"
  case sb = "SB"
  case bb = "BB"
  case utg = "UTG"
  case utg1 = "UTG+1"
  case utg2 = "UTG+2"
  case lj = "LJ"
  case hj = "HJ"
  case co = "CO"
}

/// Identical naming to TableKit's `TablePositions` (Curriculum cannot import TableKit).
public enum SeatPositions {
  /// Names for `count` players listed clockwise from the button.
  public static func names(count: Int) -> [SeatPositionName] {
    switch count {
    case ..<2: return [.btn]
    case 2: return [.btn, .bb]
    default:
      let middle: [SeatPositionName]
      switch count - 3 {
      case 0: middle = []
      case 1: middle = [.co]
      case 2: middle = [.utg, .co]
      case 3: middle = [.utg, .hj, .co]
      case 4: middle = [.utg, .lj, .hj, .co]
      case 5: middle = [.utg, .utg1, .lj, .hj, .co]
      default: middle = [.utg, .utg1, .utg2, .lj, .hj, .co]
      }
      return [.btn, .sb, .bb] + middle
    }
  }

  /// Seat index to position for seats `0..<seatCount`, with the button on seat `button`.
  public static func assign(button: Int, seatCount: Int) -> [Int: SeatPositionName] {
    guard seatCount > 0, (0..<seatCount).contains(button) else { return [:] }
    let names = names(count: seatCount)
    var result: [Int: SeatPositionName] = [:]
    for offset in 0..<seatCount { result[(button + offset) % seatCount] = names[offset] }
    return result
  }

  /// The seat holding position `p`, nil if `p` is not used at this seat count.
  public static func seat(of p: SeatPositionName, button: Int, seatCount: Int) -> Int? {
    assign(button: button, seatCount: seatCount).first { $0.value == p }?.key
  }
}

public enum MadeHandName: String, ContentEnum {
  case noPair, underPair, bottomPair, middlePair, topPair, topPairWeakKicker, topPairGoodKicker, overpair
  case twoPair, trips, set, straight, flush, fullHouse, quads

  public var classes: Set<MadeHandClass> {
    switch self {
    case .noPair: [.noPair]
    case .underPair: [.underPair]
    case .bottomPair: [.bottomPair]
    case .middlePair: [.middlePair]
    case .topPair: [.topPairWeakKicker, .topPairGoodKicker]
    case .topPairWeakKicker: [.topPairWeakKicker]
    case .topPairGoodKicker: [.topPairGoodKicker]
    case .overpair: [.overpair]
    case .twoPair: [.twoPair]
    case .trips: [.trips]
    case .set: [.set]
    case .straight: [.straight]
    case .flush: [.flush]
    case .fullHouse: [.fullHouse]
    case .quads: [.quadsPlus]
    }
  }
}

public enum DrawName: String, ContentEnum {
  case none, flushDraw, nutFlushDraw, openEnded, gutshot, combo, backdoorFlush, anyDraw
}

public enum HandCategoryName: String, ContentEnum {
  case highCard, pair, twoPair, trips, straight, flush, fullHouse, quads, straightFlush

  public var category: HandCategory {
    switch self {
    case .highCard: .highCard
    case .pair: .pair
    case .twoPair: .twoPair
    case .trips: .threeOfAKind
    case .straight: .straight
    case .flush: .flush
    case .fullHouse: .fullHouse
    case .quads: .fourOfAKind
    case .straightFlush: .straightFlush
    }
  }

  public init(_ category: HandCategory) {
    switch category {
    case .highCard: self = .highCard
    case .pair: self = .pair
    case .twoPair: self = .twoPair
    case .threeOfAKind: self = .trips
    case .straight: self = .straight
    case .flush: self = .flush
    case .fullHouse: self = .fullHouse
    case .fourOfAKind: self = .quads
    case .straightFlush: self = .straightFlush
    }
  }
}

public enum TextureTag: String, ContentEnum {
  case paired, unpaired, trips, monotone, twoTone, rainbow, flushPossible, flushDrawPossible
  case straightPossible, connected, dry, wet
}
