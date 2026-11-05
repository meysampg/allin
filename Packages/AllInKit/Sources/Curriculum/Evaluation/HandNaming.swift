import Foundation
import PokerCore
import PokerEquity

/// Plain-English names of hands for prompts and verdicts.
enum HandNaming {
  /// Preflop: "Ace-Seven suited", "Pocket Aces". Otherwise the made hand, with the strongest draw appended.
  static func heroHandName(hole: [Card], board: [Card]) -> String {
    guard hole.count == 2 else { return "" }
    guard (3...5).contains(board.count) else { return preflopName(hole) }
    let features = HandFeatures(hole: hole, board: board)
    var name = madeName(features.made)
    if features.made < .straight, let draw = drawName(features.draws) {
      name += " and \(draw)"
    }
    return name
  }

  static func preflopName(_ hole: [Card]) -> String {
    let sorted = hole.sorted { $0.rank > $1.rank }
    let high = sorted[0].rank
    let low = sorted[1].rank
    if high == low { return "Pocket \(HandDescription.pluralName(high))" }
    return
      "\(HandDescription.rankName(high))-\(HandDescription.rankName(low)) \(sorted[0].suit == sorted[1].suit ? "suited" : "offsuit")"
  }

  static func madeName(_ made: MadeHandClass) -> String {
    switch made {
    case .noPair: "no pair"
    case .underPair: "an underpair"
    case .bottomPair: "bottom pair"
    case .middlePair: "middle pair"
    case .topPairWeakKicker: "top pair, weak kicker"
    case .topPairGoodKicker: "top pair, good kicker"
    case .overpair: "an overpair"
    case .twoPair: "two pair"
    case .trips: "trips"
    case .set: "a set"
    case .straight: "a straight"
    case .flush: "a flush"
    case .fullHouse: "a full house"
    case .quadsPlus: "four of a kind"
    }
  }

  static func drawName(_ draws: DrawInfo) -> String? {
    if draws.isCombo { return "a combo draw" }
    if draws.nutFlushDraw { return "the nut flush draw" }
    if draws.flushDraw { return "a flush draw" }
    if draws.openEnded { return "an open-ended straight draw" }
    if draws.gutshot { return "a gutshot" }
    if draws.backdoorFlush { return "a backdoor flush draw" }
    return nil
  }

  /// "Two Pair", "Three of a Kind".
  static func categoryTitle(_ name: HandCategoryName) -> String { name.category.title }
}
