@testable import PokerCore

/// Plays complete hands with random legal actions and logs them. Deterministic per seed.
enum EventsRandomHands {
  struct Played {
    let log: EventLog
    let state: HandState
    let holeCards: [Int: [Card]]
  }

  static func play(seed: UInt64, handID: HandID = 1) throws -> Played {
    var rng = SeededRNG(seed: seed &* 0x9E37_79B9 &+ 17)
    let seatCount = [2, 3, 6, 9].randomElement(using: &rng)!
    let ante = Int.random(in: 0...2, using: &rng) == 0 ? 10 : 0
    let config = try TableConfig(
      seatCount: seatCount, smallBlind: 50, bigBlind: 100, ante: ante,
      anteKind: Bool.random(using: &rng) ? .perPlayer : .bigBlind)
    let stacks = (0..<seatCount).map { SeatStack(seat: $0, stack: Int.random(in: 150...6000, using: &rng)) }
    let button = Int.random(in: 0..<seatCount, using: &rng)
    var step = try HandReducer.start(
      config: config, button: button, stacks: stacks, seed: seed, burnsCards: Int.random(in: 0...4, using: &rng) > 0)
    var steps = [step]
    var guardCount = 0
    while let legal = step.state.legalActions, guardCount < 500 {
      guardCount += 1
      step = try HandReducer.apply(choose(legal, &rng), to: step.state)
      steps.append(step)
    }
    let holes = Dictionary(uniqueKeysWithValues: step.state.seats.map { ($0.seat, $0.holeCards) })
    return Played(log: EventLog(handID: handID, steps: steps), state: step.state, holeCards: holes)
  }

  static func choose(_ legal: LegalActions, _ rng: inout SeededRNG) -> Action {
    let roll = Int.random(in: 0..<100, using: &rng)
    if let range = legal.raiseRange, roll < 30, let kind = legal.raiseKind {
      let to = Int.random(in: range, using: &rng)
      let rounded = to == range.upperBound ? to : max(range.lowerBound, to - to % legal.chipUnit)
      return kind == .bet ? .bet(to: rounded) : .raise(to: rounded)
    }
    if roll < 36, legal.canAllIn { return .allIn }
    if legal.canCheck { return .check }
    if roll < 80, legal.canCall { return .call }
    if legal.callIsAllIn { return roll < 90 ? .allIn : .fold }
    return .fold
  }
}
