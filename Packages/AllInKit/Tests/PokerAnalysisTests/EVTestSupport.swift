import PokerCore
import PokerEquity

@testable import PokerAnalysis

/// A strategy from a closure of weighted actions (weights are normalized).
struct ClosureStrategy: StrategyProvider {
  let choose: @Sendable (DecisionContext) -> [(Action, Double)]

  init(_ choose: @escaping @Sendable (DecisionContext) -> [(Action, Double)]) { self.choose = choose }

  func distribution(for context: DecisionContext) -> ActionDistribution {
    let weights = choose(context).map { (action: $0.0, weight: $0.1) }
    return try! ActionDistribution(weights: weights, legal: context.legal)
  }
}

/// Checks when it can, otherwise calls.
struct AlwaysCall: StrategyProvider {
  func distribution(for context: DecisionContext) -> ActionDistribution {
    try! ActionDistribution(certain: context.legal.canCheck ? .check : .call, legal: context.legal)
  }
}

/// Checks when it can, otherwise folds.
struct CheckFold: StrategyProvider {
  func distribution(for context: DecisionContext) -> ActionDistribution {
    try! ActionDistribution(certain: context.legal.canCheck ? .check : .fold, legal: context.legal)
  }
}

struct BuiltSpot {
  let spot: EVSpot
  let state: HandState
}

func cards(_ text: String) -> [Card] { try! Card.parseList(text) }

func range(_ combos: String...) -> HandRange {
  var weights = [Float](repeating: 0, count: 1326)
  for text in combos { weights[try! Combo(text).index] = 1 }
  return HandRange(weights: weights)
}

/// Deals the requested cards (small blind 1, big blind 2), plays `actions` and returns the hero's spot.
func spot(
  heroSeat: Int, seatCount: Int, button: Int, stacks: [Int], holes: [Int: String], board: String,
  actions: [Action]
) throws -> BuiltSpot {
  let boardCards = cards(board)
  let holeCards = holes.mapValues { cards($0) }
  let used = CardSet(boardCards + holeCards.values.flatMap { $0 })
  let rest = Card.all.filter { !used.contains($0) }
  let seats = Array(0..<seatCount)
  guard
    let deck = DeckLayout.deck(
      button: button, seats: seats, burnsCards: true, holes: holeCards, board: boardCards, rest: rest)
  else { throw EVError.invalidSpot("bad test deck") }
  let config = try TableConfig(seatCount: seatCount, smallBlind: 1, bigBlind: 2)
  var steps = [
    try HandReducer.start(
      config: config, button: button, stacks: seats.map { SeatStack(seat: $0, stack: stacks[$0]) }, deck: deck)
  ]
  for action in actions { steps.append(try HandReducer.apply(action, to: steps.last!.state)) }
  let log = EventLog(handID: HandID(1), steps: steps)
  var start: HandStart?
  for logged in log.events {
    if case .handStarted(let s) = logged.event { start = s }
  }
  let records = steps.flatMap(\.records)
  let state = steps.last!.state
  guard let start,
    let context = DecisionContext.make(from: state, for: heroSeat, history: ActionEntry.entries(from: records))
  else { throw EVError.invalidSpot("hero is not to act") }
  return BuiltSpot(spot: EVSpot(start: start, priorActions: actions, context: context), state: state)
}

/// Heads-up river spot: seat 0 (button) raised to 20, seat 1 called, the board checked through.
/// Hero is seat 1 (first to act) holding the nut flush; `extra` actions follow on the river.
let riverBoard = "2h 7h Kh 4c 9d"
let checkedToRiver: [Action] = [.raise(to: 20), .call, .check, .check, .check, .check]
