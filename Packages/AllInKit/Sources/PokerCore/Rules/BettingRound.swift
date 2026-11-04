/// A seat and its chips, input to the betting-round factories.
public struct SeatStack: Codable, Sendable, Hashable {
  public let seat: Int
  public let stack: Int
  /// Postflop only: the player folded earlier in the hand.
  public let folded: Bool
  public init(seat: Int, stack: Int, folded: Bool = false) {
    self.seat = seat
    self.stack = stack
    self.folded = folded
  }
}

/// Why a betting round could not be created.
public enum BettingRoundError: Error, Sendable, Equatable {
  case tooFewPlayers
  case seatOutOfRange(Int)
  case duplicateSeat(Int)
  case buttonNotSeated(Int)
  case nonPositiveStack(seat: Int)
}

/// Forced bets posted at the start of a hand.
public struct Posting: Codable, Sendable, Hashable {
  public enum Kind: String, Codable, Sendable, Hashable { case ante, smallBlind, bigBlind }
  public let seat: Int
  public let kind: Kind
  /// Chips actually posted (less than the nominal amount when the stack is short).
  public let amount: Int
}

/// Blind and first-to-act seats for a hand.
public struct HandPositions: Codable, Sendable, Hashable {
  public let button: Int
  public let smallBlind: Int
  public let bigBlind: Int
  /// First to act preflop (left of the big blind; heads-up, the button).
  public let firstToActPreflop: Int

  /// Positions for the occupied `seats` (any order). Heads-up, the button posts the small blind and acts first
  /// preflop (and last postflop). Returns nil with fewer than two seats or when the button is not seated.
  public init?(button: Int, seats: [Int]) {
    let order = seats.sorted()
    guard order.count >= 2, let bi = order.firstIndex(of: button) else { return nil }
    self.button = button
    if order.count == 2 {
      smallBlind = button
      bigBlind = order[1 - bi]
      firstToActPreflop = button
    } else {
      smallBlind = order[(bi + 1) % order.count]
      bigBlind = order[(bi + 2) % order.count]
      firstToActPreflop = order[(bi + 3) % order.count]
    }
  }
}

/// What a processed action did, for the event log.
public struct AppliedAction: Sendable, Hashable {
  public let seat: Int
  public let action: Action
  /// Chips moved from the stack into the street's bet.
  public let chipsAdded: Int
  public let committedAfter: Int
  public let stackAfter: Int
  public let isAllIn: Bool
  /// The action was a bet/raise of at least a full raise increment (it reopens betting for everyone).
  public let isFullRaise: Bool
  /// The action raised the current bet but by less than a full raise (all-in only).
  public let isIncompleteRaise: Bool
}

/// The betting state of one street. A pure value type: `apply` mutates a copy, nothing else is touched.
///
/// Design: the round stores, per player, the stack, the chips committed this street, the status and
/// `actedAtBet`: the value of `currentBet` when the player last acted (nil if not yet acted). From that:
/// - a player still owes an action if active and (never acted or behind the current bet);
/// - a player may raise if never acted, or the bet grew by at least `lastRaiseSize` since they acted. This
///   covers "an incomplete all-in does not reopen betting" and cumulative short all-ins that add up to a
///   full raise;
/// - the round is closed when nobody owes an action.
/// Antes are dead money and not part of the street bets (see ``Posting``).
public struct BettingRound: Codable, Sendable, Hashable {
  public enum Status: String, Codable, Sendable, Hashable { case active, folded, allIn }

  public struct Player: Codable, Sendable, Hashable {
    public let seat: Int
    public internal(set) var stack: Int
    public internal(set) var committed: Int
    public internal(set) var status: Status
    public internal(set) var actedAtBet: Int?
  }

  /// Players in seat order.
  public private(set) var players: [Player]
  public private(set) var currentBet: Int
  /// Increment of the last full bet/raise; the minimum bet when no bet exists.
  public private(set) var lastRaiseSize: Int
  /// Seat to act, nil when the round is closed.
  public private(set) var toAct: Int?
  public let isPreflop: Bool
  public let config: TableConfig

  // MARK: Creation

  /// Starts a hand: posts antes and blinds (short stacks post what they have and are all-in) and returns the
  /// preflop round plus the postings in order (antes, small blind, big blind).
  public static func preflop(
    config: TableConfig, button: Int, stacks: [SeatStack]
  ) throws -> (round: BettingRound, postings: [Posting]) {
    var players = try validated(config: config, stacks: stacks)
    guard let pos = HandPositions(button: button, seats: players.map(\.seat)) else {
      throw players.count < 2 ? BettingRoundError.tooFewPlayers : BettingRoundError.buttonNotSeated(button)
    }
    var postings: [Posting] = []
    func post(_ seat: Int, _ kind: Posting.Kind, _ amount: Int, toStreet: Bool) {
      let i = players.firstIndex { $0.seat == seat }!
      let paid = min(amount, players[i].stack)
      guard paid > 0 else { return }
      players[i].stack -= paid
      if toStreet { players[i].committed += paid }
      postings.append(Posting(seat: seat, kind: kind, amount: paid))
    }
    if config.ante > 0 {
      switch config.anteKind {
      case .perPlayer: for p in players { post(p.seat, .ante, config.ante, toStreet: false) }
      case .bigBlind: post(pos.bigBlind, .ante, config.ante, toStreet: false)
      }
    }
    post(pos.smallBlind, .smallBlind, config.smallBlind, toStreet: true)
    post(pos.bigBlind, .bigBlind, config.bigBlind, toStreet: true)
    for i in players.indices where players[i].stack == 0 { players[i].status = .allIn }
    var round = BettingRound(
      players: players, currentBet: config.bigBlind, lastRaiseSize: config.bigBlind, isPreflop: true,
      config: config)
    round.refreshToAct(after: pos.bigBlind)
    return (round, postings)
  }

  /// A fresh flop/turn/river round. `players` lists every seated player (folded ones with `folded: true`);
  /// zero-stack unfolded players are all-in. Action starts with the first live seat left of the button.
  public static func postflop(config: TableConfig, button: Int, players seats: [SeatStack]) throws -> BettingRound {
    var players = try validated(config: config, stacks: seats, allowZeroStack: true)
    for (i, s) in seats.sorted(by: { $0.seat < $1.seat }).enumerated() {
      players[i].status = s.folded ? .folded : (s.stack == 0 ? .allIn : .active)
    }
    var round = BettingRound(
      players: players, currentBet: 0, lastRaiseSize: config.bigBlind, isPreflop: false, config: config)
    round.refreshToAct(after: button)
    return round
  }

  private static func validated(
    config: TableConfig, stacks: [SeatStack], allowZeroStack: Bool = false
  ) throws -> [Player] {
    guard stacks.count >= 2 else { throw BettingRoundError.tooFewPlayers }
    var seen = Set<Int>()
    for s in stacks {
      guard (0..<config.seatCount).contains(s.seat) else { throw BettingRoundError.seatOutOfRange(s.seat) }
      guard seen.insert(s.seat).inserted else { throw BettingRoundError.duplicateSeat(s.seat) }
      guard s.stack > 0 || (allowZeroStack && s.stack == 0) else {
        throw BettingRoundError.nonPositiveStack(seat: s.seat)
      }
    }
    return stacks.sorted { $0.seat < $1.seat }.map {
      Player(seat: $0.seat, stack: $0.stack, committed: 0, status: .active, actedAtBet: nil)
    }
  }

  private init(players: [Player], currentBet: Int, lastRaiseSize: Int, isPreflop: Bool, config: TableConfig) {
    self.players = players
    self.currentBet = currentBet
    self.lastRaiseSize = lastRaiseSize
    self.isPreflop = isPreflop
    self.config = config
  }

  // MARK: Queries

  public var isClosed: Bool { toAct == nil }
  /// Players still in the hand (not folded).
  public var livePlayers: [Player] { players.filter { $0.status != .folded } }
  /// The only player left when everyone else folded.
  public var winnerByFold: Int? {
    let live = livePlayers
    return live.count == 1 ? live[0].seat : nil
  }
  public var totalCommitted: Int { players.reduce(0) { $0 + $1.committed } }

  public func player(at seat: Int) -> Player? { players.first { $0.seat == seat } }

  /// Options of the player to act, nil when the round is closed.
  public func legalActions() -> LegalActions? {
    guard let seat = toAct, let p = player(at: seat) else { return nil }
    return LegalActions.compute(
      seat: seat, stack: p.stack, committed: p.committed, currentBet: currentBet,
      lastRaiseSize: lastRaiseSize, canRaise: canRaise(p), chipUnit: config.chipUnit)
  }

  /// The part of the highest bet nobody matched: it must be returned to its owner at the end of the street.
  public func uncalledBet() -> (seat: Int, amount: Int)? {
    let sorted = players.sorted { $0.committed > $1.committed }
    guard let top = sorted.first, let second = sorted.dropFirst().first, top.committed > second.committed else {
      return nil
    }
    return (top.seat, top.committed - second.committed)
  }

  // MARK: Applying actions

  /// Validates and applies `action` for the player to act.
  @discardableResult
  public mutating func apply(_ action: Action) throws -> AppliedAction {
    guard let seat = toAct, let i = players.firstIndex(where: { $0.seat == seat }) else {
      throw ActionError.roundClosed
    }
    let legal = legalActions()!
    try legal.validate(action)
    let before = players[i].committed
    var full = false
    var incomplete = false
    switch action {
    case .fold:
      players[i].status = .folded
    case .check:
      break
    case .call:
      commit(i, to: before + legal.toCall)
    case .bet(let to), .raise(let to):
      (full, incomplete) = commit(i, to: to)
    case .allIn:
      (full, incomplete) = commit(i, to: before + players[i].stack)
    }
    if action != .fold { players[i].actedAtBet = currentBet }
    refreshToAct(after: seat)
    let p = players[i]
    return AppliedAction(
      seat: seat, action: action, chipsAdded: p.committed - before, committedAfter: p.committed,
      stackAfter: p.stack, isAllIn: p.status == .allIn, isFullRaise: full, isIncompleteRaise: incomplete)
  }

  // MARK: Internals

  private func canRaise(_ p: Player) -> Bool {
    guard let acted = p.actedAtBet else { return true }
    return currentBet - acted >= lastRaiseSize
  }

  private func owesAction(_ p: Player) -> Bool {
    p.status == .active && (p.actedAtBet == nil || p.committed < currentBet)
  }

  @discardableResult
  private mutating func commit(_ i: Int, to total: Int) -> (full: Bool, incomplete: Bool) {
    players[i].stack -= total - players[i].committed
    players[i].committed = total
    if players[i].stack == 0 { players[i].status = .allIn }
    guard total > currentBet else { return (false, false) }
    let size = total - currentBet
    currentBet = total
    if size >= lastRaiseSize {
      lastRaiseSize = size
      return (true, false)
    }
    return (false, true)
  }

  /// Picks the next seat that owes an action, scanning clockwise after `seat`, or closes the round.
  private mutating func refreshToAct(after seat: Int) {
    let live = livePlayers
    let actable = live.filter { $0.status == .active }
    if live.count <= 1 || actable.isEmpty || (actable.count == 1 && actable[0].committed >= currentBet) {
      toAct = nil
      return
    }
    let n = config.seatCount
    toAct =
      players.filter(owesAction).min { ($0.seat - seat - 1 + 2 * n) % n < ($1.seat - seat - 1 + 2 * n) % n }?
      .seat
  }
}
