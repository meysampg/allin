import PokerCore
import PokerEquity

/// Sample models for the catalog and render tests.
extension PotSlicesModel {
  static let sample = PotSlicesModel(pot: 150, call: 50)
}

extension OutsGlowModel {
  static let sample = OutsGlowModel(
    hole: parseCards("Ah7h"), board: parseCards("Kh9h4s"),
    outs: parseCards("2h3h4h5h6h8hThJhQh").filter { !parseCards("Ah7h").contains($0) }, unseen: 47)
}

extension TimelineModel {
  static let sample = TimelineModel(
    streets: [
      .init(name: "Preflop", board: [], actions: ["Bram raises to 6", "You call"]),
      .init(name: "Flop", board: parseCards("Kh9h4s"), actions: ["Bram bets 50", "You: your move"]),
      .init(name: "Turn", board: parseCards("Kh9h4s2c"), actions: []),
      .init(name: "River", board: parseCards("Kh9h4s2cJd"), actions: []),
    ], current: 1)
}

extension HandLadderModel {
  static let sample = HandLadderModel(highlights: [.flush: "You", .twoPair: "Bram"])
}

extension BestFiveModel {
  static let sample = BestFiveModel(
    cards: parseCards("AhKhQh2c7dJh9h"), best: parseCards("AhKhQhJh9h"), description: "Ace-high flush")
}

extension PotCounterModel {
  static let sample = PotCounterModel(
    entries: [
      .init(label: "Blinds", amount: 3), .init(label: "Raise and call", amount: 24),
      .init(label: "Flop bet", amount: 50),
    ],
    toCall: 50)
}

extension NutsScanModel {
  static let sample = NutsScanModel(
    board: parseCards("Kh9h4h"), nuts: "Ace-high flush", nutCards: parseCards("AhQh"), flushPossible: true,
    straightPossible: false, fullHousePossible: false)
}

extension WhoCallsMeModel {
  static var sample: WhoCallsMeModel {
    var cells = [[Cell]](repeating: [Cell](repeating: .none, count: 13), count: 13)
    var worse = 0.0
    var better = 0.0
    var fold = 0.0
    for r in 0..<13 {
      for c in 0..<13 {
        let strength = 26 - r - c
        let cell: Cell = strength >= 21 ? .betterCalls : (strength >= 14 ? .worseCalls : .folds)
        if r + c > 24 { continue }
        cells[r][c] = cell
        let combos = r == c ? 6.0 : (r < c ? 4.0 : 12.0)
        switch cell {
        case .betterCalls: better += combos
        case .worseCalls: worse += combos
        default: fold += combos
        }
      }
    }
    let total = worse + better + fold
    return WhoCallsMeModel(
      mode: .callers, villainName: "Vexa the Rogue", heroCards: parseCards("AhJs"), board: parseCards("Kc7d2s"),
      cells: cells, worseCalls: worse / total, betterCalls: better / total, folds: fold / total,
      betLabel: "Vexa bets 50")
  }
}

extension EquityBarsModel {
  static let sample = EquityBarsModel(priceNeeded: 0.2, chance: 0.35)
}
