import Foundation
import PokerCore

/// Reduces the seat-filtered event stream into a ``TableSnapshot`` and the cues to present each event.
/// Pure and synchronous: the scene runs it ahead of the animations.
public struct TableModel: Sendable {
  public private(set) var snapshot: TableSnapshot

  private let config: TableConfig
  private let infos: [TableSeatInfo]
  private var startStacks: [Int: Int] = [:]
  private var dealtSeats: [Int] = []
  private var holesDealt = false

  public init(config: TableConfig, seats: [TableSeatInfo], heroSeat: Int?) {
    self.config = config
    var infos: [TableSeatInfo] = []
    for index in 0..<config.seatCount {
      var info =
        seats.first { $0.seat == index } ?? TableSeatInfo(seat: index, name: "Seat \(index + 1)")
      info.isHero = index == heroSeat
      infos.append(info)
    }
    self.infos = infos
    snapshot = TableSnapshot(
      bigBlind: config.bigBlind,
      seats: infos.map { SeatSnapshot(info: $0) })
  }

  /// Applies one event and returns what to show for it. Host-only events change nothing and give no cues.
  public mutating func apply(_ event: LoggedEvent) -> [TableCue] {
    if event.visibility == .hostOnly { return [] }
    switch event.event {
    case .handStarted(let start): return handStarted(start, handID: event.handID)
    case .deckSetup, .burned, .mucked: return []
    case .blindPosted(let posting): return blindPosted(posting)
    case .holeCardsDealt(let seat, let cards): return holeCardsDealt(seat: seat, cards: cards)
    case .actionRequested(let legal): return actionRequested(legal)
    case .actionTaken(let taken): return actionTaken(taken)
    case .uncalledBetReturned(let seat, let amount): return uncalledBetReturned(seat: seat, amount: amount)
    case .potsUpdated(let pots): return potsUpdated(pots)
    case .streetDealt(let street, let cards): return streetDealt(street, cards: cards)
    case .showdown(let reveals): return showdown(reveals)
    case .potAwarded(let info): return potAwarded(info)
    case .handEnded(let result): return handEnded(result)
    }
  }

  // MARK: Handlers

  private mutating func handStarted(_ start: HandStart, handID: HandID) -> [TableCue] {
    var seats = infos.map { SeatSnapshot(info: $0) }
    startStacks = [:]
    dealtSeats = start.seats.map(\.seat).sorted()
    holesDealt = false
    for entry in start.seats where seats.indices.contains(entry.seat) {
      seats[entry.seat].stack = entry.stack
      seats[entry.seat].status = .active
      startStacks[entry.seat] = entry.stack
    }
    let positions = TablePositions.assign(button: start.button, seats: dealtSeats)
    for (seat, name) in positions where seats.indices.contains(seat) { seats[seat].positionName = name }
    snapshot = TableSnapshot(
      handID: handID, handsStarted: snapshot.handsStarted + 1, button: start.button, bigBlind: start.config.bigBlind,
      seats: seats)
    refreshPot()
    return [.newHand(button: start.button, seats: dealtSeats)]
  }

  private mutating func blindPosted(_ posting: Posting) -> [TableCue] {
    guard snapshot.seats.indices.contains(posting.seat) else { return [] }
    snapshot.seats[posting.seat].stack -= posting.amount
    if posting.kind != .ante { snapshot.seats[posting.seat].committed += posting.amount }
    if snapshot.seats[posting.seat].stack == 0 { snapshot.seats[posting.seat].status = .allIn }
    refreshPot()
    return [.postBlind(seat: posting.seat, amount: posting.amount)]
  }

  private mutating func holeCardsDealt(seat: Int, cards: [Card]) -> [TableCue] {
    var cues = dealIfNeeded()
    if snapshot.seats.indices.contains(seat) {
      snapshot.seats[seat].holeCards = cards
      cues.append(.revealHero(cards))
    }
    return cues
  }

  private mutating func actionRequested(_ legal: LegalActions) -> [TableCue] {
    let cues = dealIfNeeded()
    snapshot.toAct = legal.seat
    snapshot.legal = legal
    setToAct(legal.seat)
    return cues + [.actionRequested(seat: legal.seat)]
  }

  private mutating func actionTaken(_ taken: ActionTaken) -> [TableCue] {
    let seat = taken.seat
    guard snapshot.seats.indices.contains(seat) else { return [] }
    snapshot.seats[seat].stack = taken.stackAfter
    snapshot.seats[seat].committed = taken.committedAfter
    snapshot.seats[seat].lastAction = Self.label(taken)
    if taken.action == .fold {
      snapshot.seats[seat].status = .folded
      snapshot.seats[seat].hasCards = false
    } else if taken.isAllIn {
      snapshot.seats[seat].status = .allIn
    }
    snapshot.toAct = nil
    snapshot.legal = nil
    setToAct(nil)
    refreshPot()
    if taken.action == .fold { return [.fold(seat: seat)] }
    return [.act(seat: seat, action: taken.action, isAllIn: taken.isAllIn)]
  }

  private mutating func uncalledBetReturned(seat: Int, amount: Int) -> [TableCue] {
    guard snapshot.seats.indices.contains(seat) else { return [] }
    snapshot.seats[seat].stack += amount
    snapshot.seats[seat].committed -= amount
    refreshPot()
    return [.returnBet(seat: seat, amount: amount)]
  }

  private mutating func potsUpdated(_ pots: [PotInfo]) -> [TableCue] {
    snapshot.pots = pots
    for index in snapshot.seats.indices {
      snapshot.seats[index].committed = 0
      if snapshot.seats[index].status != .folded { snapshot.seats[index].lastAction = nil }
    }
    refreshPot()
    return [.collectBets]
  }

  private mutating func streetDealt(_ street: Street, cards: [Card]) -> [TableCue] {
    var cues = dealIfNeeded()
    // The engine only reports the pots at the end of the hand, so a new street is what sweeps the bets: every
    // seat's stack goes to the pot, folded or not.
    if snapshot.seats.contains(where: { $0.committed > 0 }) { cues.append(.collectBets) }
    for index in snapshot.seats.indices {
      snapshot.seats[index].committed = 0
      if snapshot.seats[index].status != .folded { snapshot.seats[index].lastAction = nil }
    }
    snapshot.board += cards
    snapshot.street = street
    return cues + [.dealBoard(street, cards)]
  }

  private mutating func showdown(_ reveals: [Reveal]) -> [TableCue] {
    snapshot.showdown = reveals
    for reveal in reveals where snapshot.seats.indices.contains(reveal.seat) {
      snapshot.seats[reveal.seat].holeCards = reveal.holeCards
      snapshot.seats[reveal.seat].hasCards = true
    }
    return [.showdown(reveals)]
  }

  private mutating func potAwarded(_ info: PotAwardInfo) -> [TableCue] {
    for share in info.shares where snapshot.seats.indices.contains(share.seat) {
      snapshot.seats[share.seat].stack += share.amount
    }
    for winner in info.winners where snapshot.seats.indices.contains(winner) {
      snapshot.seats[winner].isWinner = true
    }
    refreshPot()
    return [.award(info)]
  }

  private mutating func handEnded(_ result: HandResult) -> [TableCue] {
    snapshot.result = result
    snapshot.isHandOver = true
    snapshot.toAct = nil
    snapshot.legal = nil
    setToAct(nil)
    for entry in result.finalStacks where snapshot.seats.indices.contains(entry.seat) {
      snapshot.seats[entry.seat].stack = entry.amount
    }
    for index in snapshot.seats.indices { snapshot.seats[index].committed = 0 }
    refreshPot()
    return [.handEnded(result)]
  }

  // MARK: Helpers

  /// The first sign that the hand is under way deals the hole cards.
  private mutating func dealIfNeeded() -> [TableCue] {
    guard !holesDealt, !dealtSeats.isEmpty else { return [] }
    holesDealt = true
    for seat in dealtSeats where snapshot.seats.indices.contains(seat) { snapshot.seats[seat].hasCards = true }
    let button = snapshot.button ?? dealtSeats[0]
    let start = dealtSeats.firstIndex { $0 > button } ?? 0
    let round = (0..<dealtSeats.count).map { dealtSeats[(start + $0) % dealtSeats.count] }
    return [.dealHoles(order: round + round)]
  }

  private mutating func setToAct(_ seat: Int?) {
    for index in snapshot.seats.indices { snapshot.seats[index].isToAct = index == seat }
  }

  /// Chips in the middle: what the dealt seats started with minus what they hold now.
  private mutating func refreshPot() {
    var total = 0
    for (seat, start) in startStacks where snapshot.seats.indices.contains(seat) {
      total += start - snapshot.seats[seat].stack
    }
    snapshot.potTotal = max(total, 0)
  }

  static func label(_ taken: ActionTaken) -> String {
    switch taken.action {
    case .fold: "Fold"
    case .check: "Check"
    case .call: taken.isAllIn ? "All-in \(taken.chipsAdded)" : "Call \(taken.chipsAdded)"
    case .bet(let to): "Bet \(to)"
    case .raise(let to): "Raise to \(to)"
    case .allIn: "All-in \(taken.chipsAdded)"
    }
  }
}
