import PokerCore

/// Poker statistics of one seat over many hands. Works on host or seat-filtered logs (actions, streets and
/// showdowns are public). Ratios are fractions in 0...1 (0 when there is no denominator).
public struct PlayerStats: Codable, Sendable, Hashable {
  public private(set) var hands = 0
  public private(set) var vpipHands = 0
  public private(set) var pfrHands = 0
  public private(set) var threeBetChances = 0
  public private(set) var threeBets = 0
  public private(set) var sawFlop = 0
  public private(set) var wentToShowdown = 0
  public private(set) var wonAtShowdown = 0
  public private(set) var postflopAggressive = 0
  public private(set) var postflopCalls = 0
  public private(set) var netChips = 0
  public private(set) var netBB = 0.0

  public init() {}

  public var vpip: Double { ratio(vpipHands, hands) }
  public var pfr: Double { ratio(pfrHands, hands) }
  public var threeBet: Double { ratio(threeBets, threeBetChances) }
  /// Postflop (bets + raises) / calls; with no calls, the number of aggressive actions.
  public var aggressionFactor: Double {
    postflopCalls == 0 ? Double(postflopAggressive) : Double(postflopAggressive) / Double(postflopCalls)
  }
  /// Went to showdown / saw the flop.
  public var wtsd: Double { ratio(wentToShowdown, sawFlop) }
  /// Won at showdown / went to showdown.
  public var wsd: Double { ratio(wonAtShowdown, wentToShowdown) }
  public var bbPer100: Double { hands == 0 ? 0 : netBB / Double(hands) * 100 }

  public mutating func record(_ log: EventLog, seat: Int) {
    var bigBlind = 0
    var dealtIn = false
    var folded = false
    var street = Street.preflop
    var preflopRaises = 0
    var voluntary = false
    var raisedPreflop = false
    var chance = false
    var threeBet = false
    var flopSeen = false
    var winner = false
    var result: HandResult?
    var postAggressive = 0
    var postCalls = 0
    for logged in log.events {
      switch logged.event {
      case .handStarted(let start):
        bigBlind = start.config.bigBlind
        dealtIn = start.seats.contains { $0.seat == seat }
      case .actionTaken(let taken):
        let aggressive = Self.isAggressive(taken)
        if street == .preflop {
          if taken.seat == seat {
            if preflopRaises == 1 { chance = true }
            if taken.action != .check && taken.action != .fold { voluntary = true }
            if aggressive {
              raisedPreflop = true
              if preflopRaises == 1 { threeBet = true }
            }
          }
          if aggressive { preflopRaises += 1 }
        } else if taken.seat == seat {
          if aggressive {
            postAggressive += 1
          } else if taken.action != .check && taken.action != .fold {
            postCalls += 1
          }
        }
        if taken.seat == seat, taken.action == .fold { folded = true }
      case .streetDealt(let dealt, _):
        street = dealt
        if dealt == .flop, !folded { flopSeen = true }
      case .potAwarded(let award):
        if award.winners.contains(seat) { winner = true }
      case .handEnded(let r): result = r
      default: break
      }
    }
    guard dealtIn else { return }
    hands += 1
    if voluntary { vpipHands += 1 }
    if raisedPreflop { pfrHands += 1 }
    if chance { threeBetChances += 1 }
    if threeBet { threeBets += 1 }
    if flopSeen { sawFlop += 1 }
    postflopAggressive += postAggressive
    postflopCalls += postCalls
    guard let result else { return }
    let net = result.netChips(of: seat) ?? 0
    netChips += net
    netBB += Double(net) / Double(max(bigBlind, 1))
    if flopSeen, !folded, result.reason == .showdown {
      wentToShowdown += 1
      if winner { wonAtShowdown += 1 }
    }
  }

  private static func isAggressive(_ taken: ActionTaken) -> Bool {
    switch taken.action {
    case .bet, .raise: true
    case .allIn: taken.isFullRaise || taken.isIncompleteRaise
    default: false
    }
  }

  private func ratio(_ a: Int, _ b: Int) -> Double { b == 0 ? 0 : Double(a) / Double(b) }
}
