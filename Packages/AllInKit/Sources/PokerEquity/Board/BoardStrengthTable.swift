import PokerCore

/// Per-combo card indices and masks, built once, so board code never touches `Combo` accessors in hot loops.
enum ComboTable {
  static let low: [UInt8] = table.low
  static let high: [UInt8] = table.high
  static let bits: [UInt64] = table.bits

  private static let table: (low: [UInt8], high: [UInt8], bits: [UInt64]) = {
    var lo: [UInt8] = []
    var hi: [UInt8] = []
    var bits: [UInt64] = []
    lo.reserveCapacity(1326)
    hi.reserveCapacity(1326)
    bits.reserveCapacity(1326)
    for j in 1..<52 {
      for i in 0..<j {
        lo.append(UInt8(i))
        hi.append(UInt8(j))
        bits.append((1 << UInt64(i)) | (1 << UInt64(j)))
      }
    }
    return (lo, hi, bits)
  }()
}

/// Cheap draw estimate used for range narrowing: flush draw 9, open-ended 8, gutshot 4, capped at 15.
enum DrawEstimate {
  static func outs(boardRanks: UInt16, boardSuits: [Int], low: UInt8, high: UInt8) -> Int {
    let c1 = Card(index: low)
    let c2 = Card(index: high)
    let s1 = Int(c1.suit.rawValue)
    let s2 = Int(c2.suit.rawValue)
    var total = 0
    if s1 == s2 {
      if boardSuits[s1] + 2 == 4 { total += 9 }
    } else {
      if boardSuits[s1] + 1 == 4 || boardSuits[s2] + 1 == 4 { total += 9 }
    }
    let holeMask: UInt16 = (1 << UInt16(c1.rank.rawValue)) | (1 << UInt16(c2.rank.rawValue))
    let all = RankMasks.expand(boardRanks | holeMask)
    let hole = RankMasks.expand(holeMask)
    var missing: UInt16 = 0
    for w in RankMasks.windows {
      let present = all & w
      let n = present.nonzeroBitCount
      if n == 5 { return min(total, 15) }  // already a straight
      if n == 4 && hole & w != 0 { missing |= w & ~present }
    }
    // Distinct completing ranks (the ace counts once).
    var ranks: UInt16 = 0
    var bits = missing
    while bits != 0 {
      let b = bits.trailingZeroBitCount
      ranks |= 1 << UInt16(RankMasks.rank(ofExpandedBit: b))
      bits &= bits - 1
    }
    let n = ranks.nonzeroBitCount
    if n >= 2 { total += 8 } else if n == 1 { total += 4 }
    return min(total, 15)
  }
}

/// Every combo's value on one board, evaluated once, with strength ranks and weighted range percentiles.
public struct BoardStrengthTable: Sendable {
  public let board: [Card]
  /// Raw `HandValue` per combo index; 0 for combos that hit the board.
  private let raw: [UInt16]
  /// Dense rank of the value among live values, 0 = best.
  private let dense: [UInt16]
  private let distinct: Int
  private let strengths: [Float]
  private let boardRanks: UInt16
  private let boardSuits: [Int]

  /// 1326 evaluations once per board. Precondition: 3 to 5 distinct cards.
  public init(board: [Card]) {
    precondition((3...5).contains(board.count), "A board has 3 to 5 cards")
    self.board = board
    let boardBits = CardSet(board).bits
    var raw = [UInt16](repeating: 0, count: 1326)
    var hist = [Int32](repeating: 0, count: 7464)
    var live = 0
    ComboTable.bits.withUnsafeBufferPointer { bits in
      for i in 0..<1326 {
        let b = bits[i]
        if b & boardBits != 0 { continue }
        let v = HandEvaluator.evaluate(CardSet(bits: boardBits | b)).rawValue
        raw[i] = v
        hist[Int(v)] += 1
        live += 1
      }
    }
    // Ascending raw = best first.
    var denseOf = [UInt16](repeating: 0, count: 7464)
    var strengthOf = [Float](repeating: 0, count: 7464)
    var better = 0
    var d = 0
    let denom = Float(max(live - 1, 1))
    for v in 1...7462 {
      let n = Int(hist[v])
      if n == 0 { continue }
      denseOf[v] = UInt16(d)
      let weaker = live - better - n
      strengthOf[v] = (Float(weaker) + 0.5 * Float(n - 1)) / denom
      d += 1
      better += n
    }
    var dense = [UInt16](repeating: 0, count: 1326)
    var strengths = [Float](repeating: 0, count: 1326)
    for i in 0..<1326 where raw[i] != 0 {
      dense[i] = denseOf[Int(raw[i])]
      strengths[i] = strengthOf[Int(raw[i])]
    }
    self.raw = raw
    self.dense = dense
    self.distinct = d
    self.strengths = strengths
    self.boardRanks = RankMasks.mask(of: board)
    var suits = [Int](repeating: 0, count: 4)
    for c in board { suits[Int(c.suit.rawValue)] += 1 }
    self.boardSuits = suits
  }

  /// nil if the combo hits a board card.
  public func value(of combo: Combo) -> HandValue? {
    let r = raw[combo.index]
    return r == 0 ? nil : HandValue(rawValue: r)
  }

  /// Cheap draw flag count: flush draw 9, open-ended 8, gutshot 4, capped at 15. 0 on the river or when dead.
  public func drawOuts(of combo: Combo) -> Int {
    drawOuts(index: combo.index)
  }

  func drawOuts(index: Int) -> Int {
    if board.count >= 5 || raw[index] == 0 { return 0 }
    return DrawEstimate.outs(
      boardRanks: boardRanks, boardSuits: boardSuits, low: ComboTable.low[index], high: ComboTable.high[index])
  }

  /// Strength rank in 0...1 among all live combos (1 = best, ties averaged). 0 for a dead combo.
  public func strength(of combo: Combo) -> Float { strengths[combo.index] }

  /// Weighted percentile within `range` (0 = best of that range), ties averaged; −1 for dead or zero-weight
  /// combos.
  public func percentiles(in range: HandRange) -> [Float] {
    var perValue = [Double](repeating: 0, count: distinct)
    var total = 0.0
    let weights = range.weights
    for i in 0..<1326 where raw[i] != 0 {
      let w = Double(weights[i])
      if w > 0 {
        perValue[Int(dense[i])] += w
        total += w
      }
    }
    var result = [Float](repeating: -1, count: 1326)
    guard total > 0 else { return result }
    var mid = perValue
    var running = 0.0
    for k in 0..<distinct {
      let t = perValue[k]
      mid[k] = (running + 0.5 * t) / total
      running += t
    }
    for i in 0..<1326 where raw[i] != 0 && weights[i] > 0 {
      result[i] = Float(mid[Int(dense[i])])
    }
    return result
  }
}
