import PokerCore

public enum MadeHandClass: Int, Sendable, Hashable, Comparable, CaseIterable, Codable {
  case noPair, underPair, bottomPair, middlePair, topPairWeakKicker, topPairGoodKicker, overpair,
    twoPair, trips, set, straight, flush, fullHouse, quadsPlus
  // Hands where the best five use no hole card count as .noPair. "Good kicker": kicker >= T, or the top
  // unpaired rank not on the board.

  public static func < (a: MadeHandClass, b: MadeHandClass) -> Bool { a.rawValue < b.rawValue }
}

public enum StrengthBucket: String, Sendable, Hashable, Codable, CaseIterable {
  case air, draw, weakMade, medium, strong, nutted
  // air: noPair without a draw; draw: noPair/weakMade with >= 8 outs; weakMade: under/bottom/middle pair;
  // medium: top pair; strong: overpair, two pair, trips, set (and straight+ that is not nutted);
  // nutted: straight+ that only <= 3% of live combos beat.
}

public struct DrawInfo: Sendable, Hashable {
  public let flushDraw: Bool
  public let nutFlushDraw: Bool
  /// Double gutters count as open-ended.
  public let openEnded: Bool
  public let gutshot: Bool
  /// Flop only.
  public let backdoorFlush: Bool
  public let backdoorStraight: Bool
  /// Unseen cards that make a straight or better for the hero (improving the current category).
  public let outs: Int
  public var isCombo: Bool { flushDraw && (openEnded || gutshot) }

  public init(
    flushDraw: Bool = false, nutFlushDraw: Bool = false, openEnded: Bool = false, gutshot: Bool = false,
    backdoorFlush: Bool = false, backdoorStraight: Bool = false, outs: Int = 0
  ) {
    self.flushDraw = flushDraw
    self.nutFlushDraw = nutFlushDraw
    self.openEnded = openEnded
    self.gutshot = gutshot
    self.backdoorFlush = backdoorFlush
    self.backdoorStraight = backdoorStraight
    self.outs = outs
  }
}

public struct HandFeatures: Sendable, Hashable {
  public let made: MadeHandClass
  public let value: HandValue
  public let draws: DrawInfo
  public let texture: BoardTexture
  /// Hole cards above the highest board rank.
  public let overcards: Int
  public let bucket: StrengthBucket

  /// Precondition: two hole cards and 3 to 5 board cards.
  public init(hole: [Card], board: [Card]) {
    precondition(hole.count == 2, "Two hole cards")
    precondition((3...5).contains(board.count), "A board has 3 to 5 cards")
    let value = HandEvaluator.evaluate(hole: hole, board: board)
    let texture = BoardAnalyzer.texture(board)
    let made = HandFeatures.classify(hole: hole, board: board, value: value)
    let draws = HandFeatures.drawInfo(hole: hole, board: board, value: value)
    self.value = value
    self.texture = texture
    self.made = made
    self.draws = draws
    self.overcards = hole.filter { $0.rank > texture.highRank }.count

    let bucket: StrengthBucket
    switch made {
    case .noPair: bucket = draws.outs >= 8 ? .draw : .air
    case .underPair, .bottomPair, .middlePair: bucket = draws.outs >= 8 ? .draw : .weakMade
    case .topPairWeakKicker, .topPairGoodKicker: bucket = .medium
    case .overpair, .twoPair, .trips, .set: bucket = .strong
    case .straight, .flush, .fullHouse, .quadsPlus:
      let table = BoardStrengthTable(board: board)
      bucket = table.strength(of: Combo(hole[0], hole[1])) >= 0.97 ? .nutted : .strong
    }
    self.bucket = bucket
  }

  // MARK: Made hand

  private static func classify(hole: [Card], board: [Card], value: HandValue) -> MadeHandClass {
    if board.count == 5 && value == HandEvaluator.evaluate(board) { return .noPair }  // the board plays
    let r1 = Int(hole[0].rank.rawValue)
    let r2 = Int(hole[1].rank.rawValue)
    var counts = [Int](repeating: 0, count: 13)
    for c in board { counts[Int(c.rank.rawValue)] += 1 }
    let pocket = r1 == r2
    switch value.category {
    case .straightFlush: return .quadsPlus
    case .fourOfAKind:
      var all = counts
      all[r1] += 1
      all[r2] += 1
      return all[r1] == 4 || all[r2] == 4 ? .quadsPlus : .noPair
    case .fullHouse: return .fullHouse
    case .flush: return .flush
    case .straight: return .straight
    case .threeOfAKind:
      if pocket && counts[r1] > 0 { return .set }
      if !pocket && (counts[r1] == 2 || counts[r2] == 2) { return .trips }
      return .noPair
    case .twoPair:
      var all = counts
      all[r1] += 1
      all[r2] += 1
      let pairs = (0..<13).reversed().filter { all[$0] >= 2 }.prefix(2)
      return pairs.contains(r1) || pairs.contains(r2) ? .twoPair : .noPair
    case .pair:
      let distinct = (0..<13).reversed().filter { counts[$0] > 0 }
      if pocket {
        if r1 > distinct[0] { return .overpair }
        if r1 < distinct[distinct.count - 1] { return .underPair }
        return .middlePair
      }
      let matched: Int
      let kicker: Int
      if counts[r1] > 0 {
        matched = r1
        kicker = r2
      } else if counts[r2] > 0 {
        matched = r2
        kicker = r1
      } else {
        return .noPair  // the pair is on the board
      }
      if matched == distinct[0] {
        let topUnseen = (0..<13).reversed().first { counts[$0] == 0 } ?? 12
        return kicker >= Int(Rank.ten.rawValue) || kicker == topUnseen ? .topPairGoodKicker : .topPairWeakKicker
      }
      return matched == distinct[distinct.count - 1] ? .bottomPair : .middlePair
    case .highCard: return .noPair
    }
  }

  // MARK: Draws

  private static func drawInfo(hole: [Card], board: [Card], value: HandValue) -> DrawInfo {
    guard board.count < 5 else { return DrawInfo() }
    let category = value.category
    let outs = BoardAnalyzer.outCount(hole: hole, board: board)

    var suitCounts = [Int](repeating: 0, count: 4)
    var holeSuits = [Int](repeating: 0, count: 4)
    for c in board { suitCounts[Int(c.suit.rawValue)] += 1 }
    for c in hole {
      suitCounts[Int(c.suit.rawValue)] += 1
      holeSuits[Int(c.suit.rawValue)] += 1
    }
    var flushDraw = false
    var nutFlushDraw = false
    var backdoorFlush = false
    if category < .flush {
      for s in 0..<4 where holeSuits[s] > 0 {
        if suitCounts[s] == 4 {
          flushDraw = true
          let boardRanks = Set(board.filter { Int($0.suit.rawValue) == s }.map { $0.rank })
          let topOffBoard = Rank.allCases.reversed().first { !boardRanks.contains($0) }
          let heroTop = hole.filter { Int($0.suit.rawValue) == s }.map { $0.rank }.max()
          if heroTop == topOffBoard { nutFlushDraw = true }
        } else if suitCounts[s] == 3 && board.count == 3 {
          backdoorFlush = true
        }
      }
    }

    var openEnded = false
    var gutshot = false
    var backdoorStraight = false
    if category < .straight {
      let boardMask = RankMasks.mask(of: board)
      let holeMask = RankMasks.mask(of: hole)
      let all = RankMasks.expand(boardMask | holeMask)
      let holeExp = RankMasks.expand(holeMask)
      var completing: UInt16 = 0
      var threes = false
      for w in RankMasks.windows {
        let present = all & w
        let n = present.nonzeroBitCount
        guard holeExp & present != 0 else { continue }
        if n == 4 {
          var bits = w & ~present
          while bits != 0 {
            completing |= 1 << UInt16(RankMasks.rank(ofExpandedBit: bits.trailingZeroBitCount))
            bits &= bits - 1
          }
        } else if n == 3 {
          threes = true
        }
      }
      let n = completing.nonzeroBitCount
      if n >= 2 {
        openEnded = true
      } else if n == 1 {
        gutshot = true
      } else if threes && board.count == 3 {
        backdoorStraight = true
      }
    }
    return DrawInfo(
      flushDraw: flushDraw, nutFlushDraw: nutFlushDraw, openEnded: openEnded, gutshot: gutshot,
      backdoorFlush: backdoorFlush && !flushDraw, backdoorStraight: backdoorStraight, outs: outs)
  }
}
