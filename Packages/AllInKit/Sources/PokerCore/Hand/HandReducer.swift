/// Why a hand could not be started or advanced.
public enum HandError: Error, Sendable, Equatable {
  /// The hand is over; no more actions are accepted.
  case handComplete
  /// A supplied deck is not 52 distinct cards.
  case invalidDeck
}

/// The authoritative rules reducer: `(HandState, Action) throws -> (HandState, [HandRecord])`.
///
/// Pure and deterministic: the same seed (or deck) and the same actions always give the same states and records.
/// A step runs the hand forward until a player must act or the hand is complete, so it also deals streets, runs out
/// the board when no more betting is possible, returns uncalled bets, shows down and pays the pots.
///
/// Dealing order: hole cards one at a time, two rounds, starting left of the button; before the flop, turn and river
/// one card is burned (when ``HandState/burnsCards``).
public enum HandReducer {
  // MARK: Start

  /// Starts a hand with a deck shuffled from `seed`. Every seat in `stacks` plays (stacks must be positive).
  public static func start(
    config: TableConfig, button: Int, stacks: [SeatStack], seed: UInt64, burnsCards: Bool = true
  ) throws -> HandStep {
    var deck = Deck()
    var rng = SeededRNG(seed: seed)
    deck.shuffle(using: &rng)
    return try begin(
      config: config, button: button, stacks: stacks, deck: Array(deck.undealt), seed: seed,
      burnsCards: burnsCards)
  }

  /// Starts a hand with an exact deck order (scripted hands, replays). `deck` must hold all 52 cards once.
  public static func start(
    config: TableConfig, button: Int, stacks: [SeatStack], deck: [Card], burnsCards: Bool = true
  ) throws -> HandStep {
    guard deck.count == 52, CardSet(deck).count == 52 else { throw HandError.invalidDeck }
    return try begin(
      config: config, button: button, stacks: stacks, deck: deck, seed: nil, burnsCards: burnsCards)
  }

  private static func begin(
    config: TableConfig, button: Int, stacks: [SeatStack], deck: [Card], seed: UInt64?, burnsCards: Bool
  ) throws -> HandStep {
    let (round, postings) = try BettingRound.preflop(config: config, button: button, stacks: stacks)
    let sorted = stacks.sorted { $0.seat < $1.seat }
    let positions = HandPositions(button: button, seats: sorted.map(\.seat))!
    var seats = sorted.map { s in
      HandSeat(
        seat: s.seat, startingStack: s.stack, stack: s.stack, holeCards: [], status: .active,
        settledContribution: 0)
    }
    var records: [HandRecord] = [
      .handStarted(
        HandStartInfo(
          config: config, button: button, smallBlindSeat: positions.smallBlind,
          bigBlindSeat: positions.bigBlind, seats: sorted.map { SeatStart(seat: $0.seat, stack: $0.stack) },
          seed: seed, burnsCards: burnsCards))
    ]
    for p in postings {
      records.append(.posted(p))
      if p.kind == .ante {
        let i = seats.firstIndex { $0.seat == p.seat }!
        seats[i].settledContribution += p.amount
      }
    }
    var state = HandState(
      config: config, button: button, seed: seed, burnsCards: burnsCards, seats: seats, board: [],
      street: .preflop, round: round, lastAggressor: nil, phase: .awaitingAction(seat: button), burned: [],
      deck: deck, deckPosition: 0)
    state.sync(from: round)

    // Hole cards: two rounds starting left of the button.
    let order = clockwiseFromButton(seats: sorted.map(\.seat), button: button)
    var first: [Int: Card] = [:]
    var second: [Int: Card] = [:]
    for seat in order { first[seat] = state.draw() }
    for seat in order { second[seat] = state.draw() }
    for seat in order {
      let i = state.seats.firstIndex { $0.seat == seat }!
      state.seats[i].holeCards = [first[seat]!, second[seat]!]
      records.append(.holeCardsDealt(seat: seat, cards: [first[seat]!, second[seat]!]))
    }
    try advance(&state, &records)
    return HandStep(state: state, records: records)
  }

  // MARK: Apply

  /// Applies the action of the player to act. Throws ``ActionError`` for an illegal action (the state is not
  /// changed) and ``HandError/handComplete`` after the end.
  public static func apply(_ action: Action, to state: HandState) throws -> HandStep {
    guard var round = state.round, !state.isComplete else { throw HandError.handComplete }
    var next = state
    let applied = try round.apply(action)
    next.round = round
    next.sync(from: round)
    if applied.isFullRaise || applied.isIncompleteRaise { next.lastAggressor = applied.seat }
    var records: [HandRecord] = [.actionApplied(applied, potAfter: next.pot)]
    try advance(&next, &records)
    return HandStep(state: next, records: records)
  }

  // MARK: Flow

  /// Runs the hand until a player must act or it is complete.
  private static func advance(_ state: inout HandState, _ records: inout [HandRecord]) throws {
    while let round = state.round {
      if let seat = round.toAct {
        records.append(.actionRequested(seat: seat, legal: round.legalActions()!))
        state.phase = .awaitingAction(seat: seat)
        return
      }
      settleStreet(&state, &records)
      let live = state.seats.filter { $0.status != .folded }
      if live.count == 1 {
        finish(&state, &records, reason: .uncontested)
        return
      }
      let canStillBet = live.filter { $0.status == .active }.count >= 2
      if state.street == .river || !canStillBet {
        while let street = state.street.next { dealStreet(&state, &records, street) }
        finish(&state, &records, reason: .showdown)
        return
      }
      try startStreet(&state, &records, state.street.next!)
    }
  }

  /// Closes the open round: moves its chips into the contributions and returns an uncalled bet.
  private static func settleStreet(_ state: inout HandState, _ records: inout [HandRecord]) {
    guard let round = state.round else { return }
    let uncalled = round.uncalledBet()
    for p in round.players {
      let i = state.seats.firstIndex { $0.seat == p.seat }!
      state.seats[i].settledContribution += p.committed
    }
    if let u = uncalled, u.amount > 0 {
      let i = state.seats.firstIndex { $0.seat == u.seat }!
      state.seats[i].settledContribution -= u.amount
      state.seats[i].stack += u.amount
      records.append(.uncalledBetReturned(seat: u.seat, amount: u.amount))
    }
    state.round = nil
  }

  private static func dealStreet(_ state: inout HandState, _ records: inout [HandRecord], _ street: Street) {
    let burn: Card? = state.burnsCards ? state.draw() : nil
    if let burn { state.burned.append(burn) }
    let cards = (0..<street.cardsDealt).map { _ in state.draw() }
    state.board += cards
    state.street = street
    records.append(.streetDealt(street, cards: cards, burned: burn))
  }

  private static func startStreet(
    _ state: inout HandState, _ records: inout [HandRecord], _ street: Street
  ) throws {
    dealStreet(&state, &records, street)
    state.round = try BettingRound.postflop(
      config: state.config, button: state.button,
      players: state.seats.map { SeatStack(seat: $0.seat, stack: $0.stack, folded: $0.status == .folded) })
    state.lastAggressor = nil
  }

  // MARK: Showdown and awards

  private static func finish(_ state: inout HandState, _ records: inout [HandRecord], reason: HandEndReason) {
    let live = state.liveSeats
    var contributions = state.seats.map {
      PotContribution(seat: $0.seat, amount: $0.settledContribution, folded: $0.status == .folded)
    }
    var breakdown = PotCalculator.calculate(contributions)
    // The street-level return normally leaves nothing here; this keeps chips conserved regardless.
    for r in breakdown.returns where r.amount > 0 {
      let i = state.seats.firstIndex { $0.seat == r.seat }!
      state.seats[i].settledContribution -= r.amount
      state.seats[i].stack += r.amount
      records.append(.uncalledBetReturned(seat: r.seat, amount: r.amount))
    }
    if !breakdown.returns.isEmpty {
      contributions = state.seats.map {
        PotContribution(seat: $0.seat, amount: $0.settledContribution, folded: $0.status == .folded)
      }
      breakdown = PotCalculator.calculate(contributions)
    }
    records.append(.potsFormed(breakdown.pots))

    var payouts: [Int: Int] = [:]
    var awardRecords: [PotAwardRecord] = []
    func record(_ distribution: PotDistribution) {
      payouts = distribution.payouts
      for a in distribution.awards {
        let pot = breakdown.pots[a.potIndex]
        awardRecords.append(
          PotAwardRecord(
            potIndex: a.potIndex, amount: pot.amount, eligibleSeats: pot.eligibleSeats, winners: a.winners,
            shares: a.winners.map { SeatChips(seat: $0, amount: a.shares[$0]!) }))
      }
    }

    switch reason {
    case .uncontested:
      // The sole survivor takes every pot; no cards are shown.
      let strengths = [live[0]: 0]
      record(try! PotDistributor.distribute(pots: breakdown.pots, strengths: strengths, button: state.button))
    case .showdown:
      var values: [Int: HandValue] = [:]
      for s in state.seats where s.status != .folded {
        values[s.seat] = HandEvaluator.evaluate(hole: s.holeCards, board: state.board)
      }
      let reveals = showdownOrder(state).map { seat -> ShowdownReveal in
        let hole = state.seat(seat)!.holeCards
        return ShowdownReveal(
          seat: seat, holeCards: hole, value: values[seat]!,
          bestFive: HandEvaluator.bestFive(hole + state.board))
      }
      records.append(.showdown(reveals))
      record(try! PotDistributor.distribute(pots: breakdown.pots, strengths: values, button: state.button))
    }
    for a in awardRecords { records.append(.potAwarded(a)) }
    for (seat, chips) in payouts {
      let i = state.seats.firstIndex { $0.seat == seat }!
      state.seats[i].stack += chips
    }
    let result = HandResult(
      reason: reason, board: state.board,
      finalStacks: state.seats.map { SeatChips(seat: $0.seat, amount: $0.stack) },
      net: state.seats.map { SeatChips(seat: $0.seat, amount: $0.stack - $0.startingStack) },
      contributions: state.seats.map { SeatChips(seat: $0.seat, amount: $0.settledContribution) })
    state.round = nil
    state.phase = .complete(result)
    records.append(.handEnded(result))
  }

  /// Seats that reach showdown in showing order: the last aggressor first, otherwise the first live seat left of
  /// the button; then clockwise.
  static func showdownOrder(_ state: HandState) -> [Int] {
    let live = Set(state.liveSeats)
    let clockwise = clockwiseFromButton(seats: state.seats.map(\.seat), button: state.button).filter(live.contains)
    guard let aggressor = state.lastAggressor, let i = clockwise.firstIndex(of: aggressor) else {
      return clockwise
    }
    return Array(clockwise[i...] + clockwise[..<i])
  }

  /// Seats ordered clockwise starting with the first seat left of the button; the button comes last.
  static func clockwiseFromButton(seats: [Int], button: Int) -> [Int] {
    seats.sorted { PotDistributor.order($0, button: button) < PotDistributor.order($1, button: button) }
  }
}

extension HandState {
  fileprivate mutating func draw() -> Card {
    defer { deckPosition += 1 }
    return deck[deckPosition]
  }

  /// Copies stacks and statuses from the betting round.
  fileprivate mutating func sync(from round: BettingRound) {
    for p in round.players {
      let i = seats.firstIndex { $0.seat == p.seat }!
      seats[i].stack = p.stack
      seats[i].status = p.status
    }
  }
}
