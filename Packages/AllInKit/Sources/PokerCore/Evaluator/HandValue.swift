/// The nine poker hand categories, weakest to strongest.
public enum HandCategory: UInt8, CaseIterable, Sendable, Comparable, Hashable {
  case highCard, pair, twoPair, threeOfAKind, straight, flush, fullHouse, fourOfAKind, straightFlush

  public static func < (a: HandCategory, b: HandCategory) -> Bool { a.rawValue < b.rawValue }

  /// Sentence-case name, for example "Two pair".
  public var name: String {
    switch self {
    case .highCard: "High card"
    case .pair: "Pair"
    case .twoPair: "Two pair"
    case .threeOfAKind: "Three of a kind"
    case .straight: "Straight"
    case .flush: "Flush"
    case .fullHouse: "Full house"
    case .fourOfAKind: "Four of a kind"
    case .straightFlush: "Straight flush"
    }
  }

  /// Title-case name, for example "Two Pair".
  public var title: String {
    name.split(separator: " ").map { $0 == "of" || $0 == "a" ? String($0) : $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
  }
}

/// The strength of a poker hand as one of 7,462 equivalence classes.
///
/// `rawValue` runs from 1 (royal flush, best) to 7462 (seven-high, worst), like the classic Cactus Kev scale.
/// `Comparable` is "higher is better": `a < b` means `a` is the weaker hand. `strength` is the same ordering as an
/// integer where bigger is better (1...7462).
public struct HandValue: Sendable, Hashable, Comparable, CustomStringConvertible {
  public static let bestRawValue: UInt16 = 1
  public static let worstRawValue: UInt16 = 7462

  /// 1 (best) ... 7462 (worst).
  public let rawValue: UInt16

  public init(rawValue: UInt16) {
    precondition((1...7462).contains(rawValue), "HandValue out of range")
    self.rawValue = rawValue
  }

  /// 1...7462, higher is better.
  public var strength: Int { 7463 - Int(rawValue) }

  public var category: HandCategory {
    switch rawValue {
    case ...10: .straightFlush
    case ...166: .fourOfAKind
    case ...322: .fullHouse
    case ...1599: .flush
    case ...1609: .straight
    case ...2467: .threeOfAKind
    case ...3325: .twoPair
    case ...6185: .pair
    default: .highCard
    }
  }

  public static func < (a: HandValue, b: HandValue) -> Bool { a.rawValue > b.rawValue }

  public var description: String { HandDescription.describe(self) }
}
