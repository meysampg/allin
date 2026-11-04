import Foundation
import PokerCore
import PokerEquity

/// The preflop range set of ``BaselineStrategy``: who opens, defends, re-raises and calls what. Weights are the
/// mixed strategy (a class at 0.5 raises half of the time). Decoded from `BaselineRanges+Generated.swift`.
public struct BaselinePreflopRanges: Sendable, Hashable {
  /// Keyed by `Key` names.
  let ranges: [String: HandRange]

  init(ranges: [String: HandRange]) { self.ranges = ranges }

  /// Parses the generated text: each value is a list of chunks joined with ", ".
  init(text: [String: [String]]) throws {
    var parsed: [String: HandRange] = [:]
    for (key, chunks) in text { parsed[key] = try HandRange(parsing: chunks.joined(separator: ", ")) }
    self.init(ranges: parsed)
  }

  public static let generated: BaselinePreflopRanges = {
    do { return try BaselinePreflopRanges(text: generatedText) } catch { return BaselinePreflopRanges(ranges: [:]) }
  }()

  // MARK: Lookup

  /// The first-in range. Heads-up only the button opens; the big blind never opens (use limped-pot logic).
  public func open(_ p: TablePosition, headsUp: Bool) -> HandRange {
    if headsUp { return p == .button ? range(Key.open(p, headsUp: true)) : .empty }
    return p == .bigBlind ? .empty : range(Key.open(p, headsUp: false))
  }

  /// What to do against one open: call, or 3-bet. Positions that cannot face the given opener are clamped to
  /// the nearest earlier opener.
  public func vsOpen(
    _ p: TablePosition, opener: TablePosition, headsUp: Bool
  ) -> (call: HandRange, threeBet: HandRange) {
    if headsUp {
      let call = range(Key.vsOpen(.bigBlind, .button, "call", headsUp: true))
      return (call, range(Key.vsOpen(.bigBlind, .button, "raise", headsUp: true)))
    }
    var pi = Key.order.firstIndex(of: p) ?? 1
    var oi = Key.order.firstIndex(of: opener) ?? 0
    if pi == 0 { pi = 1 }
    if oi >= pi { oi = pi - 1 }
    let pp = Key.order[pi]
    let oo = Key.order[oi]
    return (
      range(Key.vsOpen(pp, oo, "call", headsUp: false)), range(Key.vsOpen(pp, oo, "raise", headsUp: false))
    )
  }

  /// What the opener at `p` does against a 3-bet: call, or 4-bet.
  public func vsThreeBet(_ p: TablePosition, headsUp: Bool) -> (call: HandRange, fourBet: HandRange) {
    let pos: TablePosition = p == .bigBlind ? .cutoff : p
    return (range(Key.vsThreeBet(pos, "call", headsUp: headsUp)), range(Key.vsThreeBet(pos, "raise", headsUp: headsUp)))
  }

  /// What a 3-bettor does against a 4-bet: call, or 5-bet all-in.
  public func vsFourBet(headsUp: Bool) -> (call: HandRange, fiveBetAllIn: HandRange) {
    (range(Key.vsFourBet("call", headsUp: headsUp)), range(Key.vsFourBet("raise", headsUp: headsUp)))
  }

  private func range(_ key: String) -> HandRange { ranges[key] ?? .empty }

  /// Names of the stored ranges.
  enum Key {
    /// Action order of the 6-max positions.
    static let order: [TablePosition] = [.early, .middle, .cutoff, .button, .smallBlind, .bigBlind]

    static func open(_ p: TablePosition, headsUp: Bool) -> String { "\(headsUp ? "hu." : "")open.\(p.rawValue)" }

    static func vsOpen(_ p: TablePosition, _ opener: TablePosition, _ part: String, headsUp: Bool) -> String {
      headsUp ? "hu.vsOpen.\(part)" : "vsOpen.\(p.rawValue).\(opener.rawValue).\(part)"
    }

    static func vsThreeBet(_ p: TablePosition, _ part: String, headsUp: Bool) -> String {
      headsUp ? "hu.vsThreeBet.\(part)" : "vsThreeBet.\(p.rawValue).\(part)"
    }

    static func vsFourBet(_ part: String, headsUp: Bool) -> String { "\(headsUp ? "hu." : "")vsFourBet.\(part)" }
  }
}

/// Preflop decisions of ``BaselineStrategy``.
enum BaselinePreflop {
  private static let ordering = PreflopOrdering.standard
  /// Raises that commit more than this share of the stack become all-in.
  private static let allInShare = 0.40
  /// Even against the biggest raises the hero keeps playing this top share of all hands (when in range).
  private static let minimumFraction = 0.06

  static func distribution(
    for ctx: DecisionContext, spot: SpotFeatures, config: BaselineConfig, ranges: BaselinePreflopRanges
  ) -> ActionDistribution {
    var plan = BaselineActionPlan(ctx.legal)
    let combo = Combo(ctx.holeCards[0], ctx.holeCards[1])
    let handClass = combo.handClass
    let index = combo.index
    let percentile = ordering.percentile(of: handClass)
    let bb = ctx.config.bigBlind
    let legal = ctx.legal
    let line = spot.preflop
    let dealt = ctx.seats.map(\.seat)
    let headsUp = spot.isHeadsUp
    let position = spot.position

    /// Weight of the hero's hand in `range`, zero outside the top `fraction` of hands when `fraction` is set.
    func weight(_ range: HandRange, tighten: Double = 1) -> Double {
      let w = Double(range.weights[index])
      if w <= 0 { return 0 }
      if tighten >= 1 { return w }
      return percentile <= max(range.totalWeight / 1326 * tighten, minimumFraction) ? w : 0
    }
    func inPosition(versus seat: Int?) -> Bool {
      guard let seat else { return spot.isInPosition }
      let n = ctx.config.seatCount
      func order(_ s: Int) -> Int { (s - ctx.button + n - 1) % n }
      return order(ctx.seat) > order(seat)
    }
    func raiseTo(_ chips: Double) -> Int { Int(chips.rounded()) }

    switch line.situation {
    case .unopened:
      if legal.canCheck {
        plan.add(.check, 1)
      } else {
        let (pos, scale) = openPosition(position, seatCount: dealt.count, headsUp: headsUp)
        let w = weight(ranges.open(pos, headsUp: headsUp), tighten: scale)
        plan.addRaise(to: raiseTo(config.openRaiseBB * Double(bb)), allInShare: allInShare, w)
      }

    case .limped:
      let size = raiseTo(Double(bb) * (3 + Double(line.limpers)))
      if legal.canCheck {
        // Big blind option: raise the best hands over the limpers.
        let cap = headsUp ? 0.45 : 0.27
        plan.addRaise(to: size, allInShare: allInShare, percentile <= cap ? 0.85 : 0)
        plan.add(.check, 1)
      } else {
        let (pos, scale) = openPosition(position, seatCount: dealt.count, headsUp: headsUp)
        let range = pos == .bigBlind ? ranges.open(.cutoff, headsUp: false) : ranges.open(pos, headsUp: headsUp)
        let w = weight(range, tighten: scale)
        plan.addRaise(to: size, allInShare: allInShare, w)
        let completeCap = position == .smallBlind ? 0.50 : 0.30
        if percentile <= completeCap { plan.add(plan.callAction, 1 - w) }
      }

    case .facingOpen:
      let openerSeat = line.opener ?? line.lastRaiser
      let openerPos =
        openerSeat.map { TablePosition.of(seat: $0, button: ctx.button, seats: dealt) } ?? .cutoff
      let (call, threeBet) = ranges.vsOpen(position, opener: openerPos, headsUp: headsUp)
      var tighten = sizeFactor(raiseBB: Double(line.lastRaiseTo) / Double(bb), expected: config.openRaiseBB)
      tighten *= pow(0.85, Double(line.callersOfLastRaise))
      let multiplier = inPosition(versus: openerSeat) ? config.threeBetIP : config.threeBetOOP
      let size = raiseTo(Double(line.lastRaiseTo) * multiplier + Double(line.callersOfLastRaise * line.lastRaiseTo))
      let w3 = weight(threeBet, tighten: tighten)
      plan.addRaise(to: size, allInShare: allInShare, w3)
      plan.add(plan.callAction, min(weight(call, tighten: tighten), 1 - w3))

    case .facingThreeBet:
      let (call, fourBet) = ranges.vsThreeBet(position, headsUp: headsUp)
      let expected = config.openRaiseBB * config.threeBetOOP
      var tighten = sizeFactor(raiseBB: Double(line.lastRaiseTo) / Double(bb), expected: expected)
      let size = raiseTo(Double(line.lastRaiseTo) * config.fourBet)
      if line.heroRaises >= 1 {
        let w4 = weight(fourBet, tighten: tighten)
        plan.addRaise(to: size, allInShare: allInShare, w4)
        plan.add(plan.callAction, min(weight(call, tighten: tighten), 1 - w4))
      } else {
        // A squeeze over a call: continue with the strongest part only.
        tighten *= 0.6
        let w = min(1, weight(call, tighten: tighten) + weight(fourBet, tighten: tighten))
        plan.add(plan.callAction, w)
      }

    case .facingFourBetPlus:
      if line.heroRaises == 1 && line.raises == 3 {
        let (call, shove) = ranges.vsFourBet(headsUp: headsUp)
        let expected = config.openRaiseBB * config.threeBetOOP * config.fourBet
        let tighten = sizeFactor(raiseBB: Double(line.lastRaiseTo) / Double(bb), expected: expected)
        let w5 = weight(shove, tighten: tighten)
        plan.add(legal.canAllIn && !legal.callIsAllIn ? .allIn : plan.callAction, w5)
        plan.add(plan.callAction, min(weight(call, tighten: tighten), 1 - w5))
      } else {
        // Five-bets and beyond: only the very best hands.
        plan.add(legal.canAllIn && !legal.callIsAllIn ? .allIn : plan.callAction, percentile <= 0.03 ? 1 : 0)
      }
    }
    return plan.distribution(randomness: config.randomness)
  }

  /// Which table position and how much of its range to use at a table of `seatCount` players.
  private static func openPosition(
    _ position: TablePosition, seatCount: Int, headsUp: Bool
  ) -> (TablePosition, Double) {
    if headsUp { return (.button, 1) }
    switch position {
    case .early:
      if seatCount == 5 { return (.middle, 1) }
      return (.early, seatCount >= 7 ? 0.75 : 1)
    case .bigBlind: return (.cutoff, 1)
    default: return (position, 1)
    }
  }

  /// 1 for a raise of the expected size, smaller for bigger raises (they show a narrower range).
  private static func sizeFactor(raiseBB: Double, expected: Double) -> Double {
    let allowed = expected * 1.3
    if raiseBB <= allowed { return 1 }
    return max(0.04, allowed / raiseBB)
  }
}
