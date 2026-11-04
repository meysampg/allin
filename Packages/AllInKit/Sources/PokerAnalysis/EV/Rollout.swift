import PokerCore
import PokerEquity

/// The state of a rollout right at the hero's decision, before the candidate is applied.
struct PreparedRollout {
  var state: HandState
  var history: [ActionEntry]
  var street: Street
  var rng: SeededRNG
}

/// Everything needed to play rollouts of one spot. Rollout `i` is the same for every candidate (common random
/// numbers): it fixes the hidden cards, the deck order and the random stream.
struct RolloutPlan: Sendable {
  let spot: EVSpot
  let seed: UInt64
  let hero: (any StrategyProvider)?
  let opponents: [Int: any StrategyProvider]
  let ranges: [Int: HandRange]
  let baseSamplers: [Int: RangeSampler]
  let activeOpponents: [Int]
  let foldedSeats: [Int]
  let stacks: [SeatStack]
  let deadBase: CardSet
  let lastPolicyStreet: Int
  let stackAtDecision: Int

  init(
    spot: EVSpot, ranges: [Int: HandRange], opponents: [Int: any StrategyProvider],
    hero: (any StrategyProvider)?, seed: UInt64, policyStreets: Int
  ) throws {
    let context = spot.context
    guard context.holeCards.count == 2, context.board.count <= 5,
      CardSet(context.holeCards + context.board).count == context.holeCards.count + context.board.count
    else { throw EVError.invalidSpot("Hero cards or board are invalid") }
    let seatIDs = spot.start.seats.map(\.seat)
    guard seatIDs.contains(spot.hero) else { throw EVError.invalidSpot("The hero is not in the hand") }
    self.spot = spot
    self.seed = seed
    self.hero = hero
    self.opponents = opponents
    stacks = spot.start.seats.map { SeatStack(seat: $0.seat, stack: $0.stack) }
    let dead = CardSet(context.holeCards + context.board)
    deadBase = dead
    var active: [Int] = []
    var folded: [Int] = []
    for seat in seatIDs.sorted() where seat != spot.hero {
      if let view = context.view(of: seat), view.status != .folded {
        active.append(seat)
      } else {
        folded.append(seat)
      }
    }
    activeOpponents = active
    foldedSeats = folded
    var resolved: [Int: HandRange] = [:]
    var samplers: [Int: RangeSampler] = [:]
    for seat in active {
      let range = ranges[seat].flatMap { $0.totalWeight > 0 ? $0 : nil } ?? .full
      resolved[seat] = range
      samplers[seat] = RangeSampler(range, excluding: dead)
    }
    self.ranges = resolved
    baseSamplers = samplers
    let decisionIndex = Street.allCases.firstIndex(of: context.street) ?? 0
    lastPolicyStreet = decisionIndex + min(max(policyStreets, 1) - 1, 8)
    stackAtDecision = context.legal.stack
  }

  /// Hidden cards, deck and replay for rollout `index`.
  func prepare(index: Int) throws -> PreparedRollout {
    let context = spot.context
    var rng = SeededRNG(seed: StableSeed.mix(seed, UInt64(index)))
    var dead = deadBase
    var holes: [Int: [Card]] = [spot.hero: context.holeCards]
    for (i, seat) in activeOpponents.enumerated() {
      var sampler = i == 0 ? baseSamplers[seat]! : RangeSampler(ranges[seat]!, excluding: dead)
      if sampler.isEmpty { sampler = RangeSampler(.full, excluding: dead) }
      guard let combo = sampler.sample(using: &rng) else { throw EVError.invalidSpot("No cards left for a range") }
      holes[seat] = combo.cards
      dead = dead.union(combo.mask)
    }
    var spare = Card.all.makeIterator()
    for seat in foldedSeats {
      var cards: [Card] = []
      while cards.count < 2, let card = spare.next() {
        if dead.insert(card) { cards.append(card) }
      }
      guard cards.count == 2 else { throw EVError.invalidSpot("Not enough cards") }
      holes[seat] = cards
    }
    var deck = Deck(removing: dead)
    deck.shuffle(using: &rng)
    guard
      let order = DeckLayout.deck(
        button: spot.start.button, seats: spot.start.seats.map(\.seat), burnsCards: spot.start.burnsCards,
        holes: holes, board: context.board, rest: Array(deck.undealt))
    else { throw EVError.invalidSpot("The deck could not be built") }

    var state: HandState
    do {
      state = try HandReducer.start(
        config: spot.start.config, button: spot.start.button, stacks: stacks, deck: order,
        burnsCards: spot.start.burnsCards
      ).state
    } catch {
      throw EVError.replayMismatch
    }
    var history: [ActionEntry] = []
    var street = Street.preflop
    for action in spot.priorActions {
      do {
        let step = try HandReducer.apply(action, to: state)
        Self.record(step.records, street: &street, into: &history)
        state = step.state
      } catch {
        throw EVError.replayMismatch
      }
    }
    guard state.seatToAct == spot.hero, state.legalActions == context.legal, state.board == context.board else {
      throw EVError.replayMismatch
    }
    return PreparedRollout(state: state, history: history, street: street, rng: rng)
  }

  /// Plays the hand out after `candidate` and returns the hero's result in big blinds.
  func play(_ candidate: Action, from prepared: PreparedRollout) throws -> Double {
    var state = prepared.state
    var history = prepared.history
    var street = prepared.street
    var rng = prepared.rng
    do {
      let step = try HandReducer.apply(candidate, to: state)
      Self.record(step.records, street: &street, into: &history)
      state = step.state
    } catch {
      throw EVError.invalidSpot("Candidate \(candidate) is not legal")
    }
    var guardCount = 0
    while !state.isComplete {
      guardCount += 1
      guard guardCount < 1_000, let seat = state.seatToAct, let legal = state.legalActions else {
        throw EVError.replayMismatch
      }
      let action: Action
      if (Street.allCases.firstIndex(of: state.street) ?? 0) > lastPolicyStreet {
        action = legal.canCheck ? .check : (legal.canCall ? .call : .allIn)
      } else {
        guard let strategy = seat == spot.hero ? hero : opponents[seat] else {
          throw EVError.missingStrategy(seat: seat)
        }
        guard let context = DecisionContext.make(from: state, for: seat, history: history) else {
          throw EVError.replayMismatch
        }
        action = strategy.distribution(for: context).sample(using: &rng)
      }
      let step = try HandReducer.apply(action, to: state)
      Self.record(step.records, street: &street, into: &history)
      state = step.state
    }
    guard let final = state.result?.finalStack(of: spot.hero) else { throw EVError.replayMismatch }
    return Double(final - stackAtDecision) / Double(spot.start.config.bigBlind)
  }

  /// Appends the actions of `records` to the public history, tracking the street.
  private static func record(_ records: [HandRecord], street: inout Street, into history: inout [ActionEntry]) {
    for record in records {
      switch record {
      case .streetDealt(let s, _, _):
        street = s
      case .actionApplied(let a, _):
        history.append(
          ActionEntry(
            street: street, seat: a.seat, action: a.action, chipsAdded: a.chipsAdded,
            committedAfter: a.committedAfter, isAllIn: a.isAllIn))
      default:
        break
      }
    }
  }
}
