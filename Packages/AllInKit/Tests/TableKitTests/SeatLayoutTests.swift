import CoreGraphics
import Testing

@testable import TableKit

@Suite struct SeatLayoutTests {
  @Test(arguments: [2, 6, 9])
  func pointsAreInsideSeparatedAndHeroIsAtTheBottom(count: Int) {
    let points = SeatLayout.positions(seatCount: count, heroSeat: 0)
    #expect(points.count == count)
    for point in points.values {
      #expect(point.x > 0 && point.x < 1 && point.y > 0 && point.y < 1)
    }
    let list = Array(points.values)
    for i in list.indices {
      for j in list.indices where j > i {
        #expect(hypot(list[i].x - list[j].x, list[i].y - list[j].y) >= 0.1)
      }
    }
    let hero = points[0]!
    #expect(points.values.allSatisfy { $0.y <= hero.y })
  }

  @Test func rotationPutsTheHeroInPositionZero() {
    let points = SeatLayout.positions(seatCount: 6, heroSeat: 3)
    #expect(points[3] == CGPoint(x: 0.45, y: 0.70))
    #expect(points[4] == CGPoint(x: 0.12, y: 0.40))
    #expect(points[2] == CGPoint(x: 0.75, y: 0.66))
  }

  @Test func otherSeatCountsStayInsideToo() {
    for count in 3...8 where ![6].contains(count) {
      let points = SeatLayout.positions(seatCount: count, heroSeat: 1)
      #expect(points.count == count)
      #expect(points.values.allSatisfy { $0.x > 0 && $0.x < 1 && $0.y > 0 && $0.y < 1 })
    }
  }

  @Test func betPointIsThirtyFivePercentTowardTheCenter() {
    let bet = SeatLayout.betPoint(for: CGPoint(x: 0.12, y: 0.40))
    #expect(abs(bet.x - (0.12 + 0.38 * 0.35)) < 1e-9)
    #expect(abs(bet.y - 0.40) < 1e-9)
    #expect(SeatLayout.boardCenter == CGPoint(x: 0.5, y: 0.30))
    #expect(SeatLayout.potPoint == CGPoint(x: 0.5, y: 0.45))
  }
}
