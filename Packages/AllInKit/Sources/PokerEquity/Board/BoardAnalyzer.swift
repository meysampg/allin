import PokerCore

/// A group of live combos that share one hand value.
public struct BeatingHand: Sendable, Hashable {
  public let value: HandValue
  public let combos: [Combo]
  /// `HandDescription` text, for example "Flush, Ace high".
  public var description: String { HandDescription.describe(value) }

  public init(value: HandValue, combos: [Combo]) {
    self.value = value
    self.combos = combos
  }
}

public enum BoardAnalyzer {
  public static func texture(_ board: [Card]) -> BoardTexture { BoardTexture(board: board) }

  /// The best hand any live combo can hold, with every combo that holds it. Precondition: 3 to 5 board cards.
  public static func nuts(board: [Card], dead: CardSet = CardSet()) -> BeatingHand {
    precondition((3...5).contains(board.count), "A board has 3 to 5 cards")
    let blocked = CardSet(board).bits | dead.bits
    let boardBits = CardSet(board).bits
    var best = UInt16.max
    var combos: [Combo] = []
    for i in 0..<1326 {
      let b = ComboTable.bits[i]
      if b & blocked != 0 { continue }
      let v = HandEvaluator.evaluate(CardSet(bits: boardBits | b)).rawValue
      if v < best {
        best = v
        combos = [Combo(index: i)]
      } else if v == best {
        combos.append(Combo(index: i))
      }
    }
    return BeatingHand(value: HandValue(rawValue: best == .max ? HandValue.worstRawValue : best), combos: combos)
  }

  /// Live combos that currently beat the hero (strictly), grouped by value, strongest first.
  public static func beatingHands(hole: [Card], board: [Card]) -> [BeatingHand] {
    let boardBits = CardSet(board).bits
    let blocked = boardBits | CardSet(hole).bits
    let hero = HandEvaluator.evaluate(hole: hole, board: board).rawValue
    var groups: [UInt16: [Combo]] = [:]
    for i in 0..<1326 {
      let b = ComboTable.bits[i]
      if b & blocked != 0 { continue }
      let v = HandEvaluator.evaluate(CardSet(bits: boardBits | b)).rawValue
      if v < hero { groups[v, default: []].append(Combo(index: i)) }
    }
    return groups.keys.sorted().map { BeatingHand(value: HandValue(rawValue: $0), combos: groups[$0]!) }
  }

  /// Unseen cards that give the hero a straight or better and improve on the current category, in card
  /// order. Empty on the river.
  public static func outs(hole: [Card], board: [Card]) -> [Card] {
    guard board.count < 5 else { return [] }
    let seen = CardSet(hole + board)
    let current = HandEvaluator.evaluate(seen).category
    var result: [Card] = []
    for c in seen.complement where isOut(c, seen: seen, current: current) { result.append(c) }
    return result
  }

  static func outCount(hole: [Card], board: [Card]) -> Int {
    guard board.count < 5 else { return 0 }
    let seen = CardSet(hole + board)
    let current = HandEvaluator.evaluate(seen).category
    var n = 0
    for c in seen.complement where isOut(c, seen: seen, current: current) { n += 1 }
    return n
  }

  private static func isOut(_ card: Card, seen: CardSet, current: HandCategory) -> Bool {
    let category = HandEvaluator.evaluate(CardSet(bits: seen.bits | (1 << UInt64(card.index)))).category
    return category >= .straight && category > current
  }
}
