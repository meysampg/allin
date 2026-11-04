import PokerCore

/// One of the 169 strategically distinct starting hands: a pair ("QQ"), suited ("AKs") or offsuit ("T9o").
public struct HandClass: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
  /// All 169 classes in grid order (row-major, Ace first).
  public static let all: [HandClass] = (0..<169).map { HandClass(gridRow: $0 / 13, gridColumn: $0 % 13) }

  /// Grid index of the class of every combo index.
  static let gridIndexByCombo: [Int] = {
    Combo.all.map { combo in
      let hi = combo.high
      let lo = combo.low
      let suited = hi.suit == lo.suit
      return HandClass.gridIndex(high: hi.rank, low: lo.rank, suited: suited)
    }
  }()

  /// Combos of every class, indexed by grid index.
  private static let comboTable: [[Combo]] = {
    var table = [[Combo]](repeating: [], count: 169)
    for combo in Combo.all { table[gridIndexByCombo[combo.index]].append(combo) }
    return table
  }()

  public let high: Rank
  public let low: Rank
  public let suited: Bool

  /// Returns nil when `high < low`, or for a suited pair.
  public init?(high: Rank, low: Rank, suited: Bool) {
    guard high >= low, !(high == low && suited) else { return nil }
    self.high = high
    self.low = low
    self.suited = suited
  }

  /// Parses "AKs", "QQ", "T9o". A non-pair needs the `s` or `o` suffix.
  public init(_ text: String) throws {
    let part = try HandPart.parse(text, token: text)
    if part.high == part.low {
      guard part.suited == nil else { throw RangeParseError.invalidToken(text) }
      self.init(high: part.high, low: part.low, suited: false)!
    } else {
      guard let suited = part.suited else { throw RangeParseError.invalidToken(text) }
      self.init(high: part.high, low: part.low, suited: suited)!
    }
  }

  /// Grid cell: 0 = Ace. Above the diagonal (row < column) is suited, below is offsuit, the diagonal is pairs.
  public init(gridRow: Int, gridColumn: Int) {
    precondition((0..<13).contains(gridRow) && (0..<13).contains(gridColumn), "Grid cell out of range")
    if gridRow == gridColumn {
      high = Rank(rawValue: UInt8(12 - gridRow))!
      low = high
      suited = false
    } else if gridRow < gridColumn {
      high = Rank(rawValue: UInt8(12 - gridRow))!
      low = Rank(rawValue: UInt8(12 - gridColumn))!
      suited = true
    } else {
      high = Rank(rawValue: UInt8(12 - gridColumn))!
      low = Rank(rawValue: UInt8(12 - gridRow))!
      suited = false
    }
  }

  private static func gridIndex(high: Rank, low: Rank, suited: Bool) -> Int {
    let h = 12 - Int(high.rawValue)
    let l = 12 - Int(low.rawValue)
    if high == low { return h * 13 + h }
    return suited ? h * 13 + l : l * 13 + h
  }

  public var gridIndex: Int { HandClass.gridIndex(high: high, low: low, suited: suited) }
  public var gridRow: Int { gridIndex / 13 }
  public var gridColumn: Int { gridIndex % 13 }
  public var isPair: Bool { high == low }

  /// The 6 / 4 / 12 combos of the class, in combo-index order.
  public var combos: [Combo] { HandClass.comboTable[gridIndex] }
  public var comboCount: Int { isPair ? 6 : (suited ? 4 : 12) }

  public var description: String {
    var s = String([high.symbol, low.symbol])
    if !isPair { s.append(suited ? "s" : "o") }
    return s
  }

  public static func < (a: HandClass, b: HandClass) -> Bool {
    if a.high != b.high { return a.high < b.high }
    if a.low != b.low { return a.low < b.low }
    return !a.suited && b.suited
  }

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    do {
      try self.init(text)
    } catch {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid hand class: \(text)"))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}
