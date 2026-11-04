/// One public action of the current hand, as every seat saw it.
public struct ActionEntry: Codable, Sendable, Hashable {
  public let street: Street
  public let seat: Int
  public let action: Action
  /// Chips the action added to the pot (an all-in call for less adds less than owed).
  public let chipsAdded: Int
  /// The seat's total committed chips on `street` after the action.
  public let committedAfter: Int
  public let isAllIn: Bool

  public init(
    street: Street, seat: Int, action: Action, chipsAdded: Int, committedAfter: Int, isAllIn: Bool
  ) {
    self.street = street
    self.seat = seat
    self.action = action
    self.chipsAdded = chipsAdded
    self.committedAfter = committedAfter
    self.isAllIn = isAllIn
  }

  /// The public action history of a hand, extracted from the host's records (the street changes at each
  /// `streetDealt`). Only actions are read, so no hidden information can leak through here.
  public static func entries(from records: [HandRecord]) -> [ActionEntry] {
    var street = Street.preflop
    var result: [ActionEntry] = []
    for record in records {
      switch record {
      case .streetDealt(let s, _, _):
        street = s
      case .actionApplied(let a, _):
        result.append(
          ActionEntry(
            street: street, seat: a.seat, action: a.action, chipsAdded: a.chipsAdded,
            committedAfter: a.committedAfter, isAllIn: a.isAllIn))
      default:
        break
      }
    }
    return result
  }
}

/// What a seat can see of another seat (or itself): chips, never cards.
public struct SeatView: Codable, Sendable, Hashable {
  public let seat: Int
  /// Stack before antes and blinds.
  public let startingStack: Int
  /// Chips behind right now.
  public let stack: Int
  /// Chips committed on the current street.
  public let committedThisStreet: Int
  /// Chips in the pot from this seat in the whole hand.
  public let totalContribution: Int
  public let status: BettingRound.Status

  public init(
    seat: Int, startingStack: Int, stack: Int, committedThisStreet: Int, totalContribution: Int,
    status: BettingRound.Status
  ) {
    self.seat = seat
    self.startingStack = startingStack
    self.stack = stack
    self.committedThisStreet = committedThisStreet
    self.totalContribution = totalContribution
    self.status = status
  }
}

/// Everything a seat legitimately knows when it must act. It holds the seat's own hole cards and public
/// information only: never another player's hole cards, the burned cards or the deck.
public struct DecisionContext: Codable, Sendable, Hashable {
  public let config: TableConfig
  /// The seat that must act.
  public let seat: Int
  public let holeCards: [Card]
  public let board: [Card]
  public let street: Street
  public let button: Int
  public let smallBlindSeat: Int
  public let bigBlindSeat: Int
  /// Every seat dealt into the hand, ascending, with chips and status only.
  public let seats: [SeatView]
  /// Chips in the pot, including bets on the current street.
  public let pot: Int
  /// The public actions of the hand so far, in order (all streets).
  public let history: [ActionEntry]
  public let legal: LegalActions

  public init(
    config: TableConfig, seat: Int, holeCards: [Card], board: [Card], street: Street, button: Int,
    smallBlindSeat: Int, bigBlindSeat: Int, seats: [SeatView], pot: Int, history: [ActionEntry],
    legal: LegalActions
  ) {
    self.config = config
    self.seat = seat
    self.holeCards = holeCards
    self.board = board
    self.street = street
    self.button = button
    self.smallBlindSeat = smallBlindSeat
    self.bigBlindSeat = bigBlindSeat
    self.seats = seats
    self.pot = pot
    self.history = history
    self.legal = legal
  }

  /// Builds the context of the seat to act (host side). Returns nil when `seat` is not the seat to act.
  /// - Parameter history: public actions so far, e.g. ``ActionEntry/entries(from:)`` over the records.
  public static func make(
    from state: HandState, for seat: Int, history: [ActionEntry] = []
  ) -> DecisionContext? {
    guard state.seatToAct == seat, let legal = state.legalActions, let me = state.seat(seat),
      let positions = HandPositions(button: state.button, seats: state.seats.map(\.seat))
    else { return nil }
    let views = state.seats.map { s in
      SeatView(
        seat: s.seat, startingStack: s.startingStack, stack: s.stack,
        committedThisStreet: state.round?.player(at: s.seat)?.committed ?? 0,
        totalContribution: state.contribution(of: s.seat), status: s.status)
    }
    return DecisionContext(
      config: state.config, seat: seat, holeCards: me.holeCards, board: state.board,
      street: state.street, button: state.button, smallBlindSeat: positions.smallBlind,
      bigBlindSeat: positions.bigBlind, seats: views, pot: state.pot, history: history, legal: legal)
  }

  public func view(of seat: Int) -> SeatView? { seats.first { $0.seat == seat } }

  /// Seats still in the hand.
  public var liveSeats: [Int] { seats.filter { $0.status != .folded }.map(\.seat) }

  /// Pot odds: chips to call over the pot after calling. 0 when nothing is owed.
  public var potOdds: Double {
    let call = legal.callAmount
    return call == 0 ? 0 : Double(call) / Double(pot + call)
  }
}
