import PokerCore

/// A scripted hand with the grades the review should give the hero's decisions.
public struct GoldenHand: Sendable {
  public let name: String
  /// The complete host log.
  public let log: EventLog
  public let heroSeat: Int
  /// Seat to character id (the hero is absent).
  public let characters: [Int: String]
  public let expectedGrades: [Grade]

  public init(name: String, log: EventLog, heroSeat: Int, characters: [Int: String], expectedGrades: [Grade]) {
    self.name = name
    self.log = log
    self.heroSeat = heroSeat
    self.characters = characters
    self.expectedGrades = expectedGrades
  }
}

public enum GoldenHandError: Error, Sendable, Equatable { case badScript(String) }

public enum GoldenHands {
  /// Hand #22, cash 6-max 1/2, all stacks 200, button seat 0 (hero), SB 1 grumli, BB 2 zib, 3 vexa, 4 mott, 5 oryn.
  /// Deck via `DeckLayout`: hero Qs Th; Grumli Jh 9h; board Qc Jd 5s | 2h | 8c. Vexa, Mott and Oryn fold; the hero
  /// raises to 6; Grumli calls; Zib folds. Flop: Grumli checks, the hero bets ⅓ and is called. Turn: both check.
  /// River: Grumli checks, the hero bets ⅔ and is called.
  ///
  /// `expectedGrades` are the grades the review gives with the real roster, `BaselineStrategy` as the hero's
  /// continuation and `EVBudget.demo` (pinned by `ReviewDemoGradeTests`): [good, good, leak, good], the
  /// wireframe's. The turn check gives up about 7 bb against a calling station; the other three choices are
  /// within the sampling error of the best line.
  public static func reviewDemo() throws -> GoldenHand {
    let seats = [0, 1, 2, 3, 4, 5]
    let holes: [Int: [Card]] = [
      0: try Card.parseList("Qs Th"), 1: try Card.parseList("Jh 9h"), 2: try Card.parseList("4d 3c"),
      3: try Card.parseList("Kd 6c"), 4: try Card.parseList("7s 2c"), 5: try Card.parseList("Ad 8h"),
    ]
    let board = try Card.parseList("Qc Jd 5s 2h 8c")
    let used = Set((holes.values.flatMap { $0 } + board).map(\.index))
    let rest = Card.all.filter { !used.contains($0.index) }
    guard
      let deck = DeckLayout.deck(
        button: 0, seats: seats, burnsCards: true, holes: holes, board: board, rest: rest)
    else { throw GoldenHandError.badScript("The demo deck is invalid") }

    let config = try TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2)
    var steps = [
      try HandReducer.start(
        config: config, button: 0, stacks: seats.map { SeatStack(seat: $0, stack: 200) }, deck: deck)
    ]
    func play(_ action: Action) throws {
      steps.append(try HandReducer.apply(action, to: steps[steps.count - 1].state))
    }
    func sized(_ fraction: Double) throws -> Action {
      let state = steps[steps.count - 1].state
      guard let legal = state.legalActions,
        let action = ActionDistribution.potSizedRaises(fractions: [fraction], pot: state.pot, legal: legal).first
      else { throw GoldenHandError.badScript("No legal bet of \(fraction) pot") }
      return action
    }
    // Preflop: vexa, mott, oryn fold; hero opens; grumli calls; zib folds.
    try play(.fold)
    try play(.fold)
    try play(.fold)
    try play(.raise(to: 6))
    try play(.call)
    try play(.fold)
    // Flop.
    try play(.check)
    try play(try sized(1.0 / 3))
    try play(.call)
    // Turn.
    try play(.check)
    try play(.check)
    // River.
    try play(.check)
    try play(try sized(2.0 / 3))
    try play(.call)
    guard steps[steps.count - 1].state.isComplete else { throw GoldenHandError.badScript("The demo hand did not end") }

    return GoldenHand(
      name: "Hand #22: top pair, a missed turn bet", log: EventLog(handID: HandID(22), steps: steps), heroSeat: 0,
      characters: [1: "grumli", 2: "zib", 3: "vexa", 4: "mott", 5: "oryn"],
      expectedGrades: [.good, .good, .leak, .good])
  }
}
