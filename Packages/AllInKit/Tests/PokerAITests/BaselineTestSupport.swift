import PokerCore
import PokerEquity

@testable import PokerAI

func baselineCards(_ text: String) -> [Card] { try! Card.parseList(text) }

/// A history entry whose chips equal its "to" amount (good enough for the strategy, which reads actions only).
func baselineEntry(
  _ seat: Int, _ action: Action, to: Int, street: Street = .preflop, allIn: Bool = false
) -> ActionEntry {
  ActionEntry(street: street, seat: seat, action: action, chipsAdded: to, committedAfter: to, isAllIn: allIn)
}

/// A decision spot with `seatCount` players of equal stacks (blinds 50/100, chip unit 10).
func baselineContext(
  seatCount: Int, button: Int = 0, hero: Int, hole: String, board: String = "", street: Street,
  pot: Int, history: [ActionEntry], currentBet: Int, heroCommitted: Int = 0, lastRaiseSize: Int = 100,
  heroStack: Int = 9_000
) -> DecisionContext {
  let config = try! TableConfig(seatCount: seatCount, smallBlind: 50, bigBlind: 100, chipUnit: 10)
  let seats = (0..<seatCount).map { s in
    SeatView(
      seat: s, startingStack: 10_000, stack: s == hero ? heroStack : 9_000, committedThisStreet: 0,
      totalContribution: 0, status: .active)
  }
  let smallBlind = seatCount == 2 ? button : (button + 1) % seatCount
  let bigBlind = seatCount == 2 ? (button + 1) % seatCount : (button + 2) % seatCount
  let legal = LegalActions.compute(
    seat: hero, stack: heroStack, committed: heroCommitted, currentBet: currentBet,
    lastRaiseSize: lastRaiseSize, canRaise: true, chipUnit: 10)
  return DecisionContext(
    config: config, seat: hero, holeCards: baselineCards(hole), board: board.isEmpty ? [] : baselineCards(board),
    street: street, button: button, smallBlindSeat: smallBlind, bigBlindSeat: bigBlind, seats: seats, pot: pot,
    history: history, legal: legal)
}

/// The same spot with other hole cards (history, board and legal actions unchanged).
func baselineContext(_ context: DecisionContext, hole: [Card]) -> DecisionContext {
  DecisionContext(
    config: context.config, seat: context.seat, holeCards: hole, board: context.board, street: context.street,
    button: context.button, smallBlindSeat: context.smallBlindSeat, bigBlindSeat: context.bigBlindSeat,
    seats: context.seats, pot: context.pot, history: context.history, legal: context.legal)
}

/// Heads-up: the button (seat 0) opened to 250 and the big blind (seat 1, the hero) called, so the pot is 500 when
/// `board` is dealt (later streets are checked down). The button then bets `bet` into the hero (nothing when 0).
func baselineHeadsUpSpot(hole: String, board: String, street: Street, bet: Int) -> DecisionContext {
  var history = [
    baselineEntry(0, .raise(to: 250), to: 250),
    baselineEntry(1, .call, to: 250),
  ]
  var streets: [Street] = []
  var cursor: Street? = .flop
  while let s = cursor, s < street {
    streets.append(s)
    cursor = s.next
  }
  for s in streets {
    history.append(baselineEntry(1, .check, to: 0, street: s))
    history.append(baselineEntry(0, .check, to: 0, street: s))
  }
  if bet > 0 { history.append(baselineEntry(0, .bet(to: bet), to: bet, street: street)) }
  return baselineContext(
    seatCount: 2, button: 0, hero: 1, hole: hole, board: board, street: street, pot: 500 + bet,
    history: history, currentBet: bet, lastRaiseSize: max(bet, 100), heroStack: 9_750)
}

/// Probability that `distribution` plays an action matching `where`.
func baselineProbability(_ distribution: ActionDistribution, where match: (Action) -> Bool) -> Double {
  distribution.entries.filter { match($0.action) }.reduce(0) { $0 + $1.probability }
}

func baselineIsRaise(_ action: Action) -> Bool {
  switch action {
  case .bet, .raise, .allIn: true
  default: false
  }
}
