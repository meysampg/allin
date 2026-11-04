import CoreGraphics
import Foundation

/// Seat positions in a normalized unit rect (y down, wireframe coordinates).
/// Seats rotate so the hero sits in position 0 at the bottom.
public enum SeatLayout {
  public static let boardCenter = CGPoint(x: 0.5, y: 0.30)
  public static let potPoint = CGPoint(x: 0.5, y: 0.45)
  /// Where bets slide to from a seat.
  static let tableCenter = CGPoint(x: 0.5, y: 0.40)

  private static let ring2 = [CGPoint(x: 0.50, y: 0.70), CGPoint(x: 0.50, y: 0.14)]
  private static let ring6 = [
    CGPoint(x: 0.45, y: 0.70), CGPoint(x: 0.12, y: 0.40), CGPoint(x: 0.30, y: 0.14),
    CGPoint(x: 0.70, y: 0.14), CGPoint(x: 0.88, y: 0.40), CGPoint(x: 0.75, y: 0.66),
  ]
  private static let ring9 = [
    CGPoint(x: 0.50, y: 0.72), CGPoint(x: 0.22, y: 0.66), CGPoint(x: 0.08, y: 0.42),
    CGPoint(x: 0.20, y: 0.16), CGPoint(x: 0.40, y: 0.10), CGPoint(x: 0.60, y: 0.10),
    CGPoint(x: 0.80, y: 0.16), CGPoint(x: 0.92, y: 0.42), CGPoint(x: 0.78, y: 0.66),
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

  /// 35% of the way from the seat toward the middle of the table.
  public static func betPoint(for seatPoint: CGPoint) -> CGPoint {
    CGPoint(
      x: seatPoint.x + (tableCenter.x - seatPoint.x) * 0.35,
      y: seatPoint.y + (tableCenter.y - seatPoint.y) * 0.35)
  }

  private static func points(count: Int) -> [CGPoint] {
    let base: [CGPoint]
    switch count {
    case ...2: base = ring2
    case 3...6: base = ring6
    default: base = ring9
    }
    if base.count == count || count < 2 { return Array(base.prefix(max(count, 1))) }
    return (0..<count).map { base[$0 * base.count / count] }
  }
}
