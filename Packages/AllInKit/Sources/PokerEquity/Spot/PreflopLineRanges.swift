import PokerCore

/// Assumptions about a "reasonable" opponent's preflop ranges, as fractions of all combos.
public struct LineRangeModel: Sendable, Hashable {
  public var open: [TablePosition: Double]
  public var headsUpButtonOpen: Double
  public var limp: ClosedRange<Double>
  public var callOpen: ClosedRange<Double>
  public var headsUpCallOpen: ClosedRange<Double>
  public var threeBet: Double
  public var headsUpThreeBet: Double
  public var callThreeBet: ClosedRange<Double>
  public var fourBetPlus: Double
  /// All-in for at least 30 big blinds.
  public var preflopAllIn: Double

  public init(
    open: [TablePosition: Double] = [
      .early: 0.15, .middle: 0.19, .cutoff: 0.27, .button: 0.45, .smallBlind: 0.40,
    ],
    headsUpButtonOpen: Double = 0.80,
    limp: ClosedRange<Double> = 0.08...0.55,
    callOpen: ClosedRange<Double> = 0.04...0.30,
    headsUpCallOpen: ClosedRange<Double> = 0.12...0.70,
    threeBet: Double = 0.07,
    headsUpThreeBet: Double = 0.14,
    callThreeBet: ClosedRange<Double> = 0.03...0.14,
    fourBetPlus: Double = 0.035,
    preflopAllIn: Double = 0.06
  ) {
    self.open = open
    self.headsUpButtonOpen = headsUpButtonOpen
    self.limp = limp
    self.callOpen = callOpen
    self.headsUpCallOpen = headsUpCallOpen
    self.threeBet = threeBet
    self.headsUpThreeBet = headsUpThreeBet
    self.callThreeBet = callThreeBet
    self.fourBetPlus = fourBetPlus
    self.preflopAllIn = preflopAllIn
  }

  public static let standard = LineRangeModel()
}

public enum PreflopLineRanges {
  /// The range `seat` represents after its preflop actions in `context.history`, with the hero's cards and the
  /// board removed. A seat with no voluntary action is full (blinds, or yet to act).
  ///
  /// A call of a 4-bet or later raise uses `fourBetPlus`; a raise by the big blind over limpers uses `threeBet`.
  public static func range(
    of seat: Int, in context: DecisionContext, model: LineRangeModel = .standard
  ) -> HandRange {
    let dead = CardSet(context.holeCards + context.board)
    let position = TablePosition.of(seat: seat, button: context.button, seats: context.seats.map(\.seat))
    let headsUp = context.seats.count == 2
    let bigBlind = context.config.bigBlind

    var maxCommitted = bigBlind
    var raises = 0
    var last: HandRange?
    for entry in context.history where entry.street == .preflop {
      let isRaise = SpotFeatures.isRaise(entry, currentMax: maxCommitted)
      let isCall = entry.action == .call || (entry.action == .allIn && !isRaise)
      if entry.seat == seat && (isRaise || isCall) {
        if entry.isAllIn && entry.committedAfter >= 30 * bigBlind {
          last = .top(model.preflopAllIn)
        } else if isRaise {
          switch raises {
          case 0:
            if headsUp && position == .button {
              last = .top(model.headsUpButtonOpen)
            } else if let fraction = model.open[position] {
              last = .top(fraction)
            } else {
              last = .top(headsUp ? model.headsUpThreeBet : model.threeBet)
            }
          case 1: last = .top(headsUp ? model.headsUpThreeBet : model.threeBet)
          default: last = .top(model.fourBetPlus)
          }
        } else {
          switch raises {
          case 0: last = .band(from: model.limp.lowerBound, to: model.limp.upperBound)
          case 1:
            let r = headsUp ? model.headsUpCallOpen : model.callOpen
            last = .band(from: r.lowerBound, to: r.upperBound)
          case 2: last = .band(from: model.callThreeBet.lowerBound, to: model.callThreeBet.upperBound)
          default: last = .top(model.fourBetPlus)
          }
        }
      }
      if isRaise {
        raises += 1
        maxCommitted = entry.committedAfter
      }
    }
    return (last ?? .full).removing(dead)
  }
}
