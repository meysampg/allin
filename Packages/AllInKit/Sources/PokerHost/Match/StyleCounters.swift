import PokerCore

/// Preflop style statistics of one seat over many hands (VPIP, PFR, 3-bet, flop and showdown frequency).
public struct StyleCounters: Sendable, Hashable {
  public private(set) var hands: Int
  public private(set) var vpipHands: Int
  public private(set) var pfrHands: Int
  public private(set) var threeBetChances: Int
  public private(set) var threeBets: Int
  public private(set) var sawFlop: Int
  public private(set) var wentToShowdown: Int

  public init() {
    hands = 0
    vpipHands = 0
    pfrHands = 0
    threeBetChances = 0
    threeBets = 0
    sawFlop = 0
    wentToShowdown = 0
  }

  public var vpip: Double { hands > 0 ? Double(vpipHands) / Double(hands) : 0 }
  public var pfr: Double { hands > 0 ? Double(pfrHands) / Double(hands) : 0 }
  public var threeBetRate: Double { threeBetChances > 0 ? Double(threeBets) / Double(threeBetChances) : 0 }

  /// Records one complete hand from the reducer's records. The seat must have been dealt in.
  public mutating func record(_ records: [HandRecord], seat: Int) {
    var hand = HandTally(seat: seat)
    for record in records {
      switch record {
      case .handStarted(let info): hand.started(seats: info.seats.map(\.seat))
      case .actionApplied(let a, _):
        hand.action(
          seat: a.seat, action: a.action, chipsAdded: a.chipsAdded, raised: a.isFullRaise || a.isIncompleteRaise)
      case .streetDealt(let street, _, _): hand.street(street)
      case .showdown(let reveals): hand.showdown(seats: reveals.map(\.seat))
      default: break
      }
    }
    add(hand)
  }

  /// The same, from a hand's logged events.
  public mutating func record(_ events: [LoggedEvent], seat: Int) {
    var hand = HandTally(seat: seat)
    for logged in events {
      switch logged.event {
      case .handStarted(let info): hand.started(seats: info.seats.map(\.seat))
      case .actionTaken(let a):
        hand.action(
          seat: a.seat, action: a.action, chipsAdded: a.chipsAdded, raised: a.isFullRaise || a.isIncompleteRaise)
      case .streetDealt(let street, _): hand.street(street)
      case .showdown(let reveals): hand.showdown(seats: reveals.map(\.seat))
      case .mucked(let reveals): hand.showdown(seats: reveals.map(\.seat))
      default: break
      }
    }
    add(hand)
  }

  public mutating func merge(_ other: StyleCounters) {
    hands += other.hands
    vpipHands += other.vpipHands
    pfrHands += other.pfrHands
    threeBetChances += other.threeBetChances
    threeBets += other.threeBets
    sawFlop += other.sawFlop
    wentToShowdown += other.wentToShowdown
  }

  private mutating func add(_ t: HandTally) {
    guard t.dealtIn else { return }
    hands += 1
    if t.vpip { vpipHands += 1 }
    if t.pfr { pfrHands += 1 }
    threeBetChances += t.threeBetChances
    threeBets += t.threeBets
    if t.sawFlop { sawFlop += 1 }
    if t.reachedShowdown { wentToShowdown += 1 }
  }
}

/// One hand's facts for one seat, shared by the record and event variants.
private struct HandTally {
  let seat: Int
  var dealtIn = true
  var preflop = true
  var raisesSoFar = 0
  var vpip = false
  var pfr = false
  var threeBetChances = 0
  var threeBets = 0
  var folded = false
  var sawFlop = false
  var reachedShowdown = false

  init(seat: Int) { self.seat = seat }

  mutating func started(seats: [Int]) { dealtIn = seats.contains(seat) }

  mutating func action(seat actor: Int, action: Action, chipsAdded: Int, raised: Bool) {
    guard preflop else { return }
    if actor == seat {
      if chipsAdded > 0 { vpip = true }
      if raised { pfr = true }
      if raisesSoFar == 1 {
        threeBetChances += 1
        if raised { threeBets += 1 }
      }
      if action == .fold { folded = true }
    }
    if raised { raisesSoFar += 1 }
  }

  mutating func street(_ street: Street) {
    if street == .flop && preflop { sawFlop = !folded }
    preflop = false
  }

  mutating func showdown(seats: [Int]) { if seats.contains(seat) { reachedShowdown = true } }
}
