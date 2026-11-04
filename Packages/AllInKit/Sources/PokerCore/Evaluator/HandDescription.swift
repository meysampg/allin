/// Human-readable hand text for the coach UI.
public enum HandDescription {
  /// "Two", "Three", ... "Ace".
  public static func rankName(_ rank: Rank) -> String {
    ["Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace"][
      Int(rank.rawValue)]
  }

  /// "Twos", "Threes", ... "Aces".
  public static func pluralName(_ rank: Rank) -> String {
    let name = rankName(rank)
    return rank == .six ? name + "es" : name + "s"
  }

  /// Category name, for example "Full house".
  public static func categoryName(_ category: HandCategory) -> String { category.name }

  /// Text for a hand class, for example "Two pair, Kings and Nines" or "Straight, Five high".
  public static func describe(_ value: HandValue) -> String {
    let score = HandClasses.shared.scores[Int(value.rawValue) - 1]
    let category = value.category
    let fieldCount: Int
    switch category {
    case .straight, .straightFlush: fieldCount = 1
    case .fourOfAKind, .fullHouse: fieldCount = 2
    case .threeOfAKind, .twoPair: fieldCount = 3
    case .pair: fieldCount = 4
    case .flush, .highCard: fieldCount = 5
    }
    let r: [Rank] = (0..<fieldCount).map { Rank(rawValue: UInt8((score >> UInt32(16 - 4 * $0)) & 15))! }
    switch category {
    case .highCard: return "\(rankName(r[0])) high"
    case .pair: return "Pair of \(pluralName(r[0]))"
    case .twoPair: return "Two pair, \(pluralName(r[0])) and \(pluralName(r[1]))"
    case .threeOfAKind: return "Three of a kind, \(pluralName(r[0]))"
    case .straight: return "Straight, \(rankName(r[0])) high"
    case .flush: return "Flush, \(rankName(r[0])) high"
    case .fullHouse: return "Full house, \(pluralName(r[0])) full of \(pluralName(r[1]))"
    case .fourOfAKind: return "Four of a kind, \(pluralName(r[0]))"
    case .straightFlush: return r[0] == .ace ? "Royal flush" : "Straight flush, \(rankName(r[0])) high"
    }
  }

  /// Evaluates 5...7 cards and describes the result.
  public static func describe(cards: [Card]) -> String {
    describe(HandEvaluator.evaluate(cards))
  }
}
