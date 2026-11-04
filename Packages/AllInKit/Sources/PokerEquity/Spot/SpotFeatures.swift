import PokerCore

public enum PreflopSituation: String, Sendable, Hashable {
  case unopened, limped, facingOpen, facingThreeBet, facingFourBetPlus
}

/// The preflop betting line reconstructed from public history.
public struct PreflopLine: Sendable, Hashable {
  /// Voluntary preflop bets/raises (blinds excluded; an all-in above the bet counts).
  public let raises: Int
  /// Calls of the big blind before any raise.
  public let limpers: Int
  public let callersOfLastRaise: Int
  public let lastRaiser: Int?
  /// First raiser.
  public let opener: Int?
  public let lastRaiseTo: Int
  public let heroRaises: Int
  /// From the hero's point of view at decision time.
  public let situation: PreflopSituation
}

/// Context-derived facts about a decision spot (position, line, stack depth).
public struct SpotFeatures: Sendable, Hashable {
  public let hero: Int
  public let position: TablePosition
  /// Exactly 2 seats dealt in.
  public let isHeadsUp: Bool
  public let liveOpponents: [Int]
  /// Reconstructed from preflop history (postflop: the completed preflop).
  public let preflop: PreflopLine
  /// Last preflop raiser.
  public let preflopAggressor: Int?
  /// Hero acts last postflop among live seats.
  public let isInPosition: Bool
  /// `legal.toCall > 0`.
  public let facingBet: Bool
  /// Bets plus raises on the current street.
  public let betsThisStreet: Int
  public let lastAggressorPreviousStreet: Int?
  public let heroBetPreviousStreet: Bool
  /// Min of the hero stack and the largest live opponent stack, chips behind.
  public let effectiveStack: Int
  /// `effectiveStack / max(pot, 1)`.
  public let spr: Double

  public init(_ context: DecisionContext) {
    let hero = context.seat
    self.hero = hero
    let dealt = context.seats.map(\.seat)
    position = TablePosition.of(seat: hero, button: context.button, seats: dealt)
    isHeadsUp = dealt.count == 2
    let opponents = context.liveSeats.filter { $0 != hero }
    liveOpponents = opponents
    let line = SpotFeatures.preflopLine(context)
    preflop = line
    preflopAggressor = line.lastRaiser

    let n = context.config.seatCount
    func order(_ s: Int) -> Int { (s - context.button + n - 1) % n }
    isInPosition = opponents.allSatisfy { order($0) < order(hero) }

    facingBet = context.legal.toCall > 0
    let raises = SpotFeatures.raises(in: context.history, street: context.street, config: context.config)
    betsThisStreet = raises.count
    if let previous = SpotFeatures.previous(of: context.street) {
      let prior = SpotFeatures.raises(in: context.history, street: previous, config: context.config)
      lastAggressorPreviousStreet = prior.last
      heroBetPreviousStreet = prior.contains(hero)
    } else {
      lastAggressorPreviousStreet = nil
      heroBetPreviousStreet = false
    }

    let heroStack = context.view(of: hero)?.stack ?? context.legal.stack
    let maxOpponent = opponents.compactMap { context.view(of: $0)?.stack }.max()
    effectiveStack = maxOpponent.map { min(heroStack, $0) } ?? heroStack
    spr = Double(effectiveStack) / Double(max(context.pot, 1))
  }

  private static func previous(of street: Street) -> Street? {
    switch street {
    case .preflop: nil
    case .flop: .preflop
    case .turn: .flop
    case .river: .turn
    }
  }

  /// Seats of the bets/raises on `street`, in order.
  static func raises(in history: [ActionEntry], street: Street, config: TableConfig) -> [Int] {
    var maxCommitted = street == .preflop ? config.bigBlind : 0
    var result: [Int] = []
    for entry in history where entry.street == street {
      if isRaise(entry, currentMax: maxCommitted) {
        result.append(entry.seat)
        maxCommitted = entry.committedAfter
      }
    }
    return result
  }

  static func isRaise(_ entry: ActionEntry, currentMax: Int) -> Bool {
    switch entry.action {
    case .bet, .raise: true
    case .allIn: entry.committedAfter > currentMax
    case .fold, .check, .call: false
    }
  }

  private static func preflopLine(_ context: DecisionContext) -> PreflopLine {
    let hero = context.seat
    var maxCommitted = context.config.bigBlind
    var raises = 0
    var limpers = 0
    var callers = 0
    var lastRaiser: Int?
    var opener: Int?
    var lastRaiseTo = context.config.bigBlind
    var heroRaises = 0
    for entry in context.history where entry.street == .preflop {
      if isRaise(entry, currentMax: maxCommitted) {
        raises += 1
        lastRaiser = entry.seat
        if opener == nil { opener = entry.seat }
        lastRaiseTo = entry.committedAfter
        maxCommitted = entry.committedAfter
        callers = 0
        if entry.seat == hero { heroRaises += 1 }
      } else if entry.action == .call || entry.action == .allIn {
        if raises == 0 { limpers += 1 } else { callers += 1 }
      }
    }
    let situation: PreflopSituation
    switch raises {
    case 0:
      situation = limpers > 0 ? .limped : .unopened
    case 1:
      if opener == hero && context.legal.toCall == 0 {
        situation = limpers > 0 ? .limped : .unopened
      } else {
        situation = .facingOpen
      }
    case 2:
      situation = .facingThreeBet
    default:
      situation = .facingFourBetPlus
    }
    return PreflopLine(
      raises: raises, limpers: limpers, callersOfLastRaise: callers, lastRaiser: lastRaiser, opener: opener,
      lastRaiseTo: lastRaiseTo, heroRaises: heroRaises, situation: situation)
  }
}
