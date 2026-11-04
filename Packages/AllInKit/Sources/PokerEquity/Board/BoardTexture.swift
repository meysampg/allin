import PokerCore

/// Rank-mask helpers shared by the board code. A 13-bit rank mask has bit `r` for `Rank.rawValue == r`.
/// The 14-bit "expanded" form duplicates the ace as bit 0 so wheel straights are plain windows.
enum RankMasks {
  /// The ten straight windows over the expanded mask: window `w` covers bits `w...w+4`.
  static let windows: [UInt16] = (0..<10).map { UInt16(0b11111) << UInt16($0) }

  @inline(__always)
  static func expand(_ mask: UInt16) -> UInt16 { (mask << 1) | (mask >> 12) }

  /// Rank id (0 = two ... 12 = ace) of a bit in the expanded mask.
  @inline(__always)
  static func rank(ofExpandedBit bit: Int) -> Int { bit == 0 ? 12 : bit - 1 }

  static func mask(of cards: [Card]) -> UInt16 {
    var m: UInt16 = 0
    for c in cards { m |= 1 << UInt16(c.rank.rawValue) }
    return m
  }
}

/// Shape of a board: pairing, suits and connectedness.
public struct BoardTexture: Sendable, Hashable {
  public let cardCount: Int
  public let isPaired: Bool
  public let hasTrips: Bool
  /// Suit pattern of the flop part (the first three cards).
  public let isMonotone: Bool
  public let isTwoTone: Bool
  public let isRainbow: Bool
  /// At least three cards of one suit.
  public let flushPossible: Bool
  /// Exactly two cards of a suit and cards still to come.
  public let flushDrawPossible: Bool
  /// Some two hole cards would make a straight (three board ranks inside one five-rank window).
  public let straightPossible: Bool
  /// The most board ranks inside any five-rank window (ace plays low too), `0...5`.
  public let connectedness: Int
  public let highRank: Rank
  /// 0 (dry) ... 1 (wet); the formula is documented on `BoardTexture.wetness`.
  public let wetness: Double

  /// `wetness = clamp(0.35·(flushPossible or flushDrawPossible) + 0.15·monotone + 0.1·(connectedness ≥ 3)
  /// + 0.1·(connectedness ≥ 4) + 0.2·straightPossible + 0.1·(highRank ≤ Ten) − 0.15·isPaired, 0, 1)`.
  static func wetness(
    flushOrDraw: Bool, monotone: Bool, connectedness: Int, straightPossible: Bool, highRank: Rank, paired: Bool
  ) -> Double {
    var w = 0.0
    if flushOrDraw { w += 0.35 }
    if monotone { w += 0.15 }
    if connectedness >= 3 { w += 0.1 }
    if connectedness >= 4 { w += 0.1 }
    if straightPossible { w += 0.2 }
    if highRank <= .ten { w += 0.1 }
    if paired { w -= 0.15 }
    return min(max(w, 0), 1)
  }

  init(board: [Card]) {
    cardCount = board.count
    var rankCounts = [Int](repeating: 0, count: 13)
    var suitCounts = [Int](repeating: 0, count: 4)
    var high = Rank.two
    for c in board {
      rankCounts[Int(c.rank.rawValue)] += 1
      suitCounts[Int(c.suit.rawValue)] += 1
      if c.rank > high { high = c.rank }
    }
    highRank = high
    let maxRank = rankCounts.max() ?? 0
    isPaired = maxRank >= 2
    hasTrips = maxRank >= 3

    var flopSuits = Set<UInt8>()
    for c in board.prefix(3) { flopSuits.insert(c.suit.rawValue) }
    isMonotone = flopSuits.count == 1 && board.count >= 3
    isTwoTone = flopSuits.count == 2
    isRainbow = flopSuits.count >= 3

    let maxSuit = suitCounts.max() ?? 0
    flushPossible = maxSuit >= 3
    flushDrawPossible = board.count < 5 && suitCounts.contains(2)

    let expanded = RankMasks.expand(RankMasks.mask(of: board))
    var connected = 0
    for w in RankMasks.windows { connected = max(connected, (expanded & w).nonzeroBitCount) }
    connectedness = connected
    straightPossible = connected >= 3

    wetness = BoardTexture.wetness(
      flushOrDraw: flushPossible || flushDrawPossible, monotone: isMonotone, connectedness: connected,
      straightPossible: straightPossible, highRank: high, paired: isPaired)
  }
}
