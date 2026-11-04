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
    let bet = SeatLayout.betPoint(for: CGPoint(x: 0.13, y: 0.40))
    #expect(abs(bet.x - (0.13 + 0.37 * 0.35)) < 1e-9)
    #expect(abs(bet.y - 0.40) < 1e-9)
    #expect(SeatLayout.boardCenter == CGPoint(x: 0.5, y: 0.30))
    #expect(SeatLayout.potPoint == CGPoint(x: 0.5, y: 0.45))
  }

  @Test(arguments: [2, 6, 9])
  func betSpotsStayClearOfTheBoardPotShoeAndSeats(count: Int) {
    let points = SeatLayout.positions(seatCount: count, heroSeat: 0)
    let board = SeatLayout.boardRect
    let pot = SeatLayout.potRect
    let shoe = SeatLayout.shoeRect
    let seats = points.mapValues { SeatLayout.seatRect(at: $0) }
    let bets = points.mapValues { SeatLayout.betRect(forSeatAt: $0) }
    for (seat, bet) in bets {
      #expect(!bet.intersects(board), "bet \(seat) hits the board")
      #expect(!bet.intersects(pot), "bet \(seat) hits the pot")
      #expect(!bet.intersects(shoe), "bet \(seat) hits the shoe")
      for (other, rect) in seats { #expect(!bet.intersects(rect), "bet \(seat) hits seat \(other)") }
      for (other, rect) in bets where other != seat { #expect(!bet.intersects(rect), "bet \(seat) hits bet \(other)") }
      #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(bet))
    }
    for (seat, rect) in seats {
      #expect(!rect.intersects(shoe), "seat \(seat) hits the shoe")
      #expect(!rect.intersects(board), "seat \(seat) hits the board")
    }
  }

  @Test(arguments: [2, 6, 9])
  func heroCardsStayClearOfBoardPotAndBets(count: Int) {
    let points = SeatLayout.positions(seatCount: count, heroSeat: 0)
    let hero = SeatLayout.heroCardRect(at: points[0]!)
    #expect(!hero.intersects(SeatLayout.boardRect), "hero cards hit the board")
    #expect(!hero.intersects(SeatLayout.potRect), "hero cards hit the pot")
    #expect(!hero.intersects(SeatLayout.shoeRect), "hero cards hit the shoe")
    for (seat, point) in points {
      #expect(!hero.intersects(SeatLayout.betRect(forSeatAt: point)), "hero cards hit bet \(seat)")
      if seat != 0 { #expect(!hero.intersects(SeatLayout.seatRect(at: point)), "hero cards hit seat \(seat)") }
    }
    #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(hero))
  }
}
