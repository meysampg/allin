import PokerCore

/// How a seat's range shrinks with its postflop actions. Percentiles are within the seat's current range.
public struct NarrowingModel: Sendable, Hashable {
  /// Bet/raise: combos in the top `betKeepTop` of their range keep weight 1.
  public var betKeepTop: Double
  public var betDrawWeight: Float
  public var betOtherWeight: Float
  /// Call: the top `callTrapTop` (slow-played monsters) get weight 0.6.
  public var callTrapTop: Double
  /// Call: percentiles up to `callKeepTo` keep weight 1.
  public var callKeepTo: Double
  public var callOtherWeight: Float
  /// Check: the top 10% get this weight, because the seat could have bet.
  public var checkTopWeight: Float

  public init(
    betKeepTop: Double = 0.35, betDrawWeight: Float = 0.8, betOtherWeight: Float = 0.2,
    callTrapTop: Double = 0.08, callKeepTo: Double = 0.65, callOtherWeight: Float = 0.25,
    checkTopWeight: Float = 0.5
  ) {
    self.betKeepTop = betKeepTop
    self.betDrawWeight = betDrawWeight
    self.betOtherWeight = betOtherWeight
    self.callTrapTop = callTrapTop
    self.callKeepTo = callKeepTo
    self.callOtherWeight = callOtherWeight
    self.checkTopWeight = checkTopWeight
  }

  public static let standard = NarrowingModel()
}

public enum PerceivedRange {
  /// Draws for the narrowing rules: flush draw or open-ended (8+ flag outs).
  private static let drawThreshold = 8
  private static let callTrapWeight: Float = 0.6
  private static let checkTopFraction: Float = 0.10

  private enum Kind { case bet, call, check }

  /// Preflop line range (M2.3), then narrowed street by street using that seat's postflop actions (board prefix
  /// per street), then blended with `HandRange.full` by `blur` (0 = trust the line fully), then hero cards and
  /// board removed. `tables` caches `BoardStrengthTable` per board prefix length (3, 4, 5); reuse the same
  /// dictionary for several seats of one decision, never across hands.
  public static func estimate(
    of seat: Int, in context: DecisionContext, blur: Double,
    line: LineRangeModel = .standard, narrowing: NarrowingModel = .standard,
    tables: inout [Int: BoardStrengthTable]
  ) -> HandRange {
    var range = PreflopLineRanges.range(of: seat, in: context, model: line)
    var street = Street.flop
    var maxCommitted = 0
    for entry in context.history where entry.street > .preflop {
      if entry.street != street {
        street = entry.street
        maxCommitted = 0
      }
      let isRaise = SpotFeatures.isRaise(entry, currentMax: maxCommitted)
      if isRaise { maxCommitted = entry.committedAfter }
      guard entry.seat == seat else { continue }
      let kind: Kind
      switch entry.action {
      case .bet, .raise: kind = .bet
      case .allIn: kind = isRaise ? .bet : .call
      case .call: kind = .call
      case .check: kind = .check
      case .fold: continue
      }
      let n = entry.street == .flop ? 3 : (entry.street == .turn ? 4 : 5)
      guard context.board.count >= n else { continue }
      let table: BoardStrengthTable
      if let cached = tables[n] {
        table = cached
      } else {
        table = BoardStrengthTable(board: Array(context.board.prefix(n)))
        tables[n] = table
      }
      range = narrow(range, kind: kind, table: table, model: narrowing)
    }
    if blur > 0 { range = range.blended(with: .full, t: blur) }
    return removing(CardSet(context.holeCards + context.board), from: range)
  }

  /// Same result as `HandRange.removing`, without building a `CardSet` per combo.
  private static func removing(_ dead: CardSet, from range: HandRange) -> HandRange {
    var weights = range.weights
    let bits = dead.bits
    for i in 0..<1326 where ComboTable.bits[i] & bits != 0 { weights[i] = 0 }
    return HandRange(weights: weights)
  }

  private static func narrow(
    _ range: HandRange, kind: Kind, table: BoardStrengthTable, model: NarrowingModel
  ) -> HandRange {
    let percentiles = table.percentiles(in: range)
    var weights = range.weights
    for i in 0..<1326 {
      let p = Double(percentiles[i])
      if p < 0 { continue }
      let factor: Float
      switch kind {
      case .bet:
        if p < model.betKeepTop {
          factor = 1
        } else {
          factor = table.drawOuts(index: i) >= drawThreshold ? model.betDrawWeight : model.betOtherWeight
        }
      case .call:
        if p < model.callTrapTop {
          factor = callTrapWeight
        } else if p < model.callKeepTo {
          factor = 1
        } else {
          factor = table.drawOuts(index: i) >= drawThreshold ? 0.8 : model.callOtherWeight
        }
      case .check:
        factor = Float(p) < checkTopFraction ? model.checkTopWeight : 1
      }
      weights[i] *= factor
    }
    return HandRange(weights: weights)
  }
}
