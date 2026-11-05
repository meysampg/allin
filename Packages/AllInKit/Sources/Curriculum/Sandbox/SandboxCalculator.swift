import Foundation
import PokerCore
import PokerEquity

public struct SandboxState: Sendable, Hashable {
  public var heroCards: [Card]
  public var board: [Card]
  public var potBeforeBet: Int
  public var villainBet: Int
  /// BB ... the most the villain can bet (twice the pot, capped by the villain's stack).
  public var betRange: ClosedRange<Int>
  public var bigBlind: Int
  public var villainName: String
  /// Tracked at the decision.
  public var villainRange: HandRange

  public init(
    heroCards: [Card], board: [Card], potBeforeBet: Int, villainBet: Int, betRange: ClosedRange<Int>, bigBlind: Int,
    villainName: String, villainRange: HandRange
  ) {
    self.heroCards = heroCards
    self.board = board
    self.potBeforeBet = potBeforeBet
    self.villainBet = villainBet
    self.betRange = betRange
    self.bigBlind = bigBlind
    self.villainName = villainName
    self.villainRange = villainRange
  }
}

public struct SandboxReadings: Sendable, Hashable {
  public var priceNeeded: Double?
  public var potAfterCall: Int?
  public var outs: [Card]?
  public var bestFive: [Card]?
  public var bestFiveText: String?
  public var nutsText: String?
  public var worseInRange: Double?
  public var betterInRange: Double?

  public init(
    priceNeeded: Double? = nil, potAfterCall: Int? = nil, outs: [Card]? = nil, bestFive: [Card]? = nil,
    bestFiveText: String? = nil, nutsText: String? = nil, worseInRange: Double? = nil, betterInRange: Double? = nil
  ) {
    self.priceNeeded = priceNeeded
    self.potAfterCall = potAfterCall
    self.outs = outs
    self.bestFive = bestFive
    self.bestFiveText = bestFiveText
    self.nutsText = nutsText
    self.worseInRange = worseInRange
    self.betterInRange = betterInRange
  }
}

public enum SandboxSlot: Sendable, Hashable { case hero(Int), board(Int) }

public struct SandboxSetup: Sendable, Hashable {
  public let title: String
  public let controls: [SandboxControl]
  public let meters: [SandboxMeter]
  public let challenge: String?
  public let explainer: ExplainerKind?
  public let initial: SandboxState
  public let seed: UInt64

  public init(
    title: String, controls: [SandboxControl], meters: [SandboxMeter], challenge: String?, explainer: ExplainerKind?,
    initial: SandboxState, seed: UInt64
  ) {
    self.title = title
    self.controls = controls
    self.meters = meters
    self.challenge = challenge
    self.explainer = explainer
    self.initial = initial
    self.seed = seed
  }
}

/// The maths behind the sandbox: instant readings plus a progressive chance stream.
public enum SandboxCalculator {
  public static func initialState(_ instance: SpotInstance, villainRanges: [Int: HandRange]) -> SandboxState {
    let hero = instance.holeCards[instance.heroSeat] ?? []
    let board = instance.board
    let dead = CardSet(hero + board)
    let villain = instance.villainSeats.first
    let context = instance.state.seatToAct.flatMap {
      DecisionContext.make(from: instance.state, for: $0, history: instance.history)
    }
    let bigBlind = max(instance.config.bigBlind, 1)
    let facing = instance.actor == instance.heroSeat ? (context?.legal.toCall ?? 0) : 0
    let pot = context?.pot ?? instance.state.pot
    let potBeforeBet = max(pot - facing, 0)
    let villainBehind = villain.flatMap { v in context?.view(of: v).map { $0.stack + $0.committedThisStreet } }
    let cap = min(2 * potBeforeBet, villainBehind ?? 2 * potBeforeBet)
    let upper = max(cap, bigBlind)
    let bet = facing > 0 ? facing : max(bigBlind, (potBeforeBet + 1) / 2)
    return SandboxState(
      heroCards: hero, board: board, potBeforeBet: potBeforeBet, villainBet: min(max(bet, bigBlind), upper),
      betRange: bigBlind...upper, bigBlind: bigBlind,
      villainName: villain.flatMap { instance.seatNames[$0] } ?? "Villain",
      villainRange: (villain.flatMap { villainRanges[$0] } ?? .full).removing(dead))
  }

  /// price = villainBet / (potBeforeBet + 2·villainBet); worse/better are the shares of the villain's live range
  /// the hero beats (ties count as worse) and that beat the hero. Only the requested meters are computed.
  public static func readings(_ s: SandboxState, meters: [SandboxMeter]) -> SandboxReadings {
    var r = SandboxReadings()
    let hasBoard = s.board.count >= 3
    let heroValid = s.heroCards.count == 2
    for meter in meters {
      switch meter {
      case .priceNeeded, .yourChance:
        let denominator = s.potBeforeBet + 2 * s.villainBet
        r.priceNeeded = denominator > 0 ? Double(s.villainBet) / Double(denominator) : nil
      case .potAfter:
        r.potAfterCall = s.potBeforeBet + 2 * s.villainBet
      case .outs:
        r.outs =
          heroValid && (3...4).contains(s.board.count) ? BoardAnalyzer.outs(hole: s.heroCards, board: s.board) : []
      case .bestFive:
        if heroValid && hasBoard {
          let cards = s.heroCards + s.board
          r.bestFive = HandEvaluator.bestFive(cards)
          r.bestFiveText = HandDescription.describe(cards: cards)
        }
      case .nuts:
        if hasBoard { r.nutsText = BoardAnalyzer.nuts(board: s.board, dead: CardSet(s.heroCards)).description }
      case .worseThatCall, .betterThatCall:
        if heroValid && hasBoard {
          let split = rangeSplit(s)
          r.worseInRange = split.worse
          r.betterInRange = split.better
        }
      }
    }
    return r
  }

  /// Progressive hero chance against the tracked range. The first estimate carries one batch of 2000 samples.
  public static func chance(_ s: SandboxState, seed: UInt64, totalSamples: Int = 20_000) -> AsyncStream<EquityEstimate>
  {
    guard s.heroCards.count == 2, Set(s.heroCards).count == 2 else {
      return AsyncStream { continuation in
        continuation.yield(EquityEstimate(results: [], samples: 0, isFinal: true))
        continuation.finish()
      }
    }
    let villain = s.villainRange.removing(dead(s))
    return EquityCalculator.stream(
      [HandRange(combo: Combo(s.heroCards[0], s.heroCards[1])), villain], board: s.board, totalSamples: totalSamples,
      batch: 2000, seed: seed)
  }

  /// Puts `card` in `slot`. A card already in use elsewhere swaps places with the card it replaces.
  public static func setting(_ slot: SandboxSlot, to card: Card, in s: SandboxState) -> SandboxState {
    var next = s
    func read(_ slot: SandboxSlot) -> Card? {
      switch slot {
      case .hero(let i): next.heroCards.indices.contains(i) ? next.heroCards[i] : nil
      case .board(let i): next.board.indices.contains(i) ? next.board[i] : nil
      }
    }
    func write(_ slot: SandboxSlot, _ value: Card) {
      switch slot {
      case .hero(let i): next.heroCards[i] = value
      case .board(let i): next.board[i] = value
      }
    }
    guard let old = read(slot), old != card else { return s }
    let others: [SandboxSlot] =
      s.heroCards.indices.map { .hero($0) } + s.board.indices.map { .board($0) }
    if let holder = others.first(where: { $0 != slot && read($0) == card }) { write(holder, old) }
    write(slot, card)
    return next
  }

  /// The hero's cards and the board.
  public static func dead(_ s: SandboxState) -> CardSet { CardSet(s.heroCards + s.board) }

  private static func rangeSplit(_ s: SandboxState) -> (worse: Double, better: Double) {
    let heroValue = HandEvaluator.evaluate(hole: s.heroCards, board: s.board)
    let blocked = dead(s).bits
    var worse = 0.0
    var better = 0.0
    let boardCards = s.board
    for combo in s.villainRange.nonZeroCombos where combo.mask.bits & blocked == 0 {
      let w = Double(s.villainRange[combo])
      if HandEvaluator.evaluate(hole: combo.cards, board: boardCards) > heroValue { better += w } else { worse += w }
    }
    let total = worse + better
    return total > 0 ? (worse / total, better / total) : (0, 0)
  }
}
