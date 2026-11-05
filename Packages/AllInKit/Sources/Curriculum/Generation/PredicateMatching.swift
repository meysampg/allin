import Foundation
import PokerCore
import PokerEquity

// The `matches` functions of the content predicates. (The file is not called Predicates.swift because
// Model/Predicates.swift already uses that name inside this target.)

extension HandPredicate {
  /// True when `hole` satisfies every given key on `board`. With fewer than three board cards (preflop) only
  /// `range`, `pocketPair` and `suited` are checked; the board-dependent keys do not apply.
  public func matches(hole: [Card], board: [Card]) -> Bool {
    guard hole.count == 2 else { return false }
    if let pocketPair, (hole[0].rank == hole[1].rank) != pocketPair { return false }
    if let suited, (hole[0].suit == hole[1].suit) != suited { return false }
    if let range, !(range.range[Combo(hole[0], hole[1])] > 0) { return false }
    guard board.count >= 3 else { return true }
    if let categories {
      let category = HandEvaluator.evaluate(hole: hole, board: board).category
      if !categories.contains(where: { $0.category == category }) { return false }
    }
    if madeHand == nil && bucket == nil && draws == nil && outs == nil { return true }
    let features = HandFeatures(hole: hole, board: board)
    if let madeHand, !madeHand.contains(where: { $0.classes.contains(features.made) }) { return false }
    if let bucket, !bucket.contains(features.bucket) { return false }
    if let draws, !draws.contains(where: { $0.holds(features.draws) }) { return false }
    if let outs, !outs.range.contains(features.draws.outs) { return false }
    return true
  }
}

extension DrawName {
  /// Whether the draw description satisfies this draw name (backdoor draws only count for `backdoorFlush`).
  func holds(_ info: DrawInfo) -> Bool {
    switch self {
    case .none: !info.flushDraw && !info.openEnded && !info.gutshot
    case .flushDraw: info.flushDraw
    case .nutFlushDraw: info.nutFlushDraw
    case .openEnded: info.openEnded
    case .gutshot: info.gutshot
    case .combo: info.isCombo
    case .backdoorFlush: info.backdoorFlush
    case .anyDraw: info.flushDraw || info.openEnded || info.gutshot
    }
  }
}

extension TextureTag {
  func holds(_ texture: BoardTexture) -> Bool {
    switch self {
    case .paired: texture.isPaired
    case .unpaired: !texture.isPaired
    case .trips: texture.hasTrips
    case .monotone: texture.isMonotone
    case .twoTone: texture.isTwoTone
    case .rainbow: texture.isRainbow
    case .flushPossible: texture.flushPossible
    case .flushDrawPossible: texture.flushDrawPossible
    case .straightPossible: texture.straightPossible
    case .connected: texture.connectedness >= 3
    case .dry: texture.wetness < 0.3
    case .wet: texture.wetness >= 0.6
    }
  }
}

extension BoardPredicate {
  /// True when `board` has exactly the cards of `street` and fits every texture constraint. A preflop board is
  /// empty and has no texture, so it only matches a predicate without constraints.
  public func matches(_ board: [Card]) -> Bool {
    guard board.count == street.boardCount else { return false }
    if street == .preflop { return require.isEmpty && highCard == nil }
    let texture = BoardAnalyzer.texture(board)
    if !require.allSatisfy({ $0.holds(texture) }) { return false }
    if exclude.contains(where: { $0.holds(texture) }) { return false }
    if let highCard, !highCard.contains(texture.highRank) { return false }
    return true
  }
}

extension Street {
  /// Board cards on the table once this street is dealt: 0, 3, 4, 5.
  var boardCount: Int {
    switch self {
    case .preflop: 0
    case .flop: 3
    case .turn: 4
    case .river: 5
    }
  }
}

extension SituationPredicate {
  /// True when the decision of `context.seat` fits every given key.
  public func matches(_ context: DecisionContext) -> Bool {
    let features = SpotFeatures(context)
    if let facingBet, features.facingBet != facingBet { return false }
    if let heroInPosition, features.isInPosition != heroInPosition { return false }
    if let spr, !spr.range.contains(features.spr) { return false }
    return true
  }
}
