import Foundation
import PokerCore

/// How much of the opponent read-out the table shows.
public enum TableHUD: String, Sendable, CaseIterable {
  case off, basic, full
}

/// Who sits where, as the scene shows it.
public struct TableSeatInfo: Sendable, Hashable {
  public var seat: Int
  public var name: String
  public var characterID: String?
  public var styleHint: String?
  public var isHero: Bool

  public init(seat: Int, name: String, characterID: String? = nil, styleHint: String? = nil, isHero: Bool = false) {
    self.seat = seat
    self.name = name
    self.characterID = characterID
    self.styleHint = styleHint
    self.isHero = isHero
  }
}

public enum SeatStatus: String, Sendable, Hashable {
  case empty, active, folded, allIn
}

public struct SeatSnapshot: Sendable, Hashable {
  public var info: TableSeatInfo
  public var stack: Int
  /// Chips bet on this street, still in front of the seat.
  public var committed: Int
  public var status: SeatStatus
  public var hasCards: Bool
  /// The faces the viewer knows about (the hero's, then showdown reveals).
  public var holeCards: [Card]?
  /// BTN, SB, BB, UTG, HJ, CO ...
  public var positionName: String?
  public var lastAction: String?
  public var isToAct: Bool
  public var isWinner: Bool

  public init(
    info: TableSeatInfo, stack: Int = 0, committed: Int = 0, status: SeatStatus = .empty, hasCards: Bool = false,
    holeCards: [Card]? = nil, positionName: String? = nil, lastAction: String? = nil, isToAct: Bool = false,
    isWinner: Bool = false
  ) {
    self.info = info
    self.stack = stack
    self.committed = committed
    self.status = status
    self.hasCards = hasCards
    self.holeCards = holeCards
    self.positionName = positionName
    self.lastAction = lastAction
    self.isToAct = isToAct
    self.isWinner = isWinner
  }
}

public struct TableSnapshot: Sendable, Hashable {
  public var handID: HandID?
  public var handsStarted: Int
  public var button: Int?
  public var bigBlind: Int
  /// By seat index, `0..<seatCount`.
  public var seats: [SeatSnapshot]
  public var board: [Card]
  public var street: Street
  /// Settled pots.
  public var pots: [PotInfo]
  /// Every chip in the middle, including the bets still in front of the seats.
  public var potTotal: Int
  public var toAct: Int?
  public var legal: LegalActions?
  public var showdown: [Reveal]
  public var result: HandResult?
  public var isHandOver: Bool

  public init(
    handID: HandID? = nil, handsStarted: Int = 0, button: Int? = nil, bigBlind: Int = 0, seats: [SeatSnapshot] = [],
    board: [Card] = [], street: Street = .preflop, pots: [PotInfo] = [], potTotal: Int = 0, toAct: Int? = nil,
    legal: LegalActions? = nil, showdown: [Reveal] = [], result: HandResult? = nil, isHandOver: Bool = false
  ) {
    self.handID = handID
    self.handsStarted = handsStarted
    self.button = button
    self.bigBlind = bigBlind
    self.seats = seats
    self.board = board
    self.street = street
    self.pots = pots
    self.potTotal = potTotal
    self.toAct = toAct
    self.legal = legal
    self.showdown = showdown
    self.result = result
    self.isHandOver = isHandOver
  }

  public func seat(_ index: Int) -> SeatSnapshot? {
    seats.indices.contains(index) ? seats[index] : nil
  }
}
