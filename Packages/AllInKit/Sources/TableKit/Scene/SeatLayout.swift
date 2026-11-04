import CoreGraphics
import Foundation

/// Seat positions in a normalized unit rect (y down, wireframe coordinates).
/// Seats rotate so the hero sits in position 0 at the bottom.
public enum SeatLayout {
  public static let boardCenter = CGPoint(x: 0.5, y: 0.30)
  public static let potPoint = CGPoint(x: 0.5, y: 0.45)
  /// Where bets slide to from a seat.
  static let tableCenter = CGPoint(x: 0.5, y: 0.40)

  /// Where the dealer shoe sits: the top-right corner of the rail, clear of every seat for 2, 6 and 9 players.
  public static let shoePoint = CGPoint(x: 1075.0 / 1120, y: 105.0 / 700)

  private static let baseWidth: CGFloat = 1120
  private static let baseHeight: CGFloat = 700

  /// A point given in base-layout points (1120 x 700, y down).
  private static func unit(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x / baseWidth, y: y / baseHeight)
  }

  private typealias Spot = (seat: CGPoint, bet: CGPoint)

  // Bet spots sit beside the seat, on the side facing the middle of the table, and stay clear of the board, the pot
  // and every seat block (cards, medallion, name box and style hint).
  private static let ring2: [Spot] = [
    (CGPoint(x: 0.50, y: 0.70), unit(448, 470)),
    (CGPoint(x: 0.50, y: 0.12), unit(672, 119)),
  ]
  private static let ring6: [Spot] = [
    (CGPoint(x: 0.45, y: 0.70), unit(392, 470)), (CGPoint(x: 0.12, y: 0.40), unit(246, 280)),
    (CGPoint(x: 0.30, y: 0.12), unit(448, 119)), (CGPoint(x: 0.70, y: 0.12), unit(672, 119)),
    (CGPoint(x: 0.88, y: 0.40), unit(874, 280)), (CGPoint(x: 0.75, y: 0.66), unit(728, 462)),
  ]
  private static let ring9: [Spot] = [
    (CGPoint(x: 0.50, y: 0.72), unit(448, 470)), (CGPoint(x: 0.22, y: 0.66), unit(358, 462)),
    (CGPoint(x: 0.08, y: 0.42), unit(202, 294)), (CGPoint(x: 0.13, y: 0.16), unit(258, 119)),
    (CGPoint(x: 0.35, y: 0.10), unit(504, 119)), (CGPoint(x: 0.65, y: 0.10), unit(616, 119)),
    (CGPoint(x: 0.87, y: 0.16), unit(862, 119)), (CGPoint(x: 0.92, y: 0.42), unit(918, 294)),
    (CGPoint(x: 0.78, y: 0.66), unit(762, 462)),
  ]

  /// Keys are seat indices. Layouts exist for 2, 6 and 9 seats; other sizes use an evenly spread subset of the
  /// next larger ring. Without a hero, seat 0 takes position 0.
  public static func positions(seatCount: Int, heroSeat: Int?) -> [Int: CGPoint] {
    let count = min(max(seatCount, 1), 9)
    let ring = points(count: count)
    let hero = heroSeat ?? 0
    var result: [Int: CGPoint] = [:]
    for seat in 0..<count {
      let k = ((seat - hero) % count + count) % count
      result[seat] = ring[k]
    }
    return result
  }

  /// Where a seat's bet stack rests. Seats of the 2, 6 and 9 rings have a hand-placed spot; any other point
  /// gets one 35% of the way toward the middle of the table.
  public static func betPoint(for seatPoint: CGPoint) -> CGPoint {
    for ring in [ring2, ring6, ring9] {
      if let spot = ring.first(where: { $0.seat == seatPoint }) { return spot.bet }
    }
    return CGPoint(
      x: seatPoint.x + (tableCenter.x - seatPoint.x) * 0.35,
      y: seatPoint.y + (tableCenter.y - seatPoint.y) * 0.35)
  }

  // MARK: Occupied areas (normalized, y down)

  /// The five board cards, with room for the showdown lift.
  public static var boardRect: CGRect { rect(x: 396, y: 160, width: 328, height: 100) }

  /// The pot chips and caption.
  public static var potRect: CGRect { rect(x: 500, y: 278, width: 120, height: 72) }

  /// The dealer shoe sprite.
  public static var shoeRect: CGRect {
    let c = shoePoint
    return CGRect(x: c.x - 17 / baseWidth, y: c.y - 24 / baseHeight, width: 34 / baseWidth, height: 48 / baseHeight)
  }

  /// Everything a seat draws: cards above the medallion, the name box and the style hint below.
  public static func seatRect(at seatPoint: CGPoint) -> CGRect {
    CGRect(
      x: seatPoint.x - 69 / baseWidth, y: seatPoint.y - 95 / baseHeight, width: 138 / baseWidth,
      height: 169 / baseHeight)
  }

  /// The bet chips and their label.
  public static func betRect(forSeatAt seatPoint: CGPoint) -> CGRect {
    let c = betPoint(for: seatPoint)
    return CGRect(
      x: c.x - 40 / baseWidth, y: c.y - 33 / baseHeight, width: 80 / baseWidth, height: 65 / baseHeight)
  }

  private static func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: x / baseWidth, y: y / baseHeight, width: width / baseWidth, height: height / baseHeight)
  }

  private static func points(count: Int) -> [CGPoint] {
    let base: [CGPoint]
    switch count {
    case ...2: base = ring2.map(\.seat)
    case 3...6: base = ring6.map(\.seat)
    default: base = ring9.map(\.seat)
    }
    if base.count == count || count < 2 { return Array(base.prefix(max(count, 1))) }
    return (0..<count).map { base[$0 * base.count / count] }
  }
}
