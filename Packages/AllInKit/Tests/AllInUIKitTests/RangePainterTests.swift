import CoreGraphics
import Testing

@testable import AllInUI

@Suite struct RangePainterTests {
  private let empty = [[Float]](repeating: [Float](repeating: 0, count: 13), count: 13)

  @Test func clickToggles() {
    var logic = RangePainterLogic(weights: empty)
    #expect(logic.toggle(row: 0, column: 0) == 1)
    #expect(logic.weights[0][0] == 1)
    #expect(logic.toggle(row: 0, column: 0) == 0)
    #expect(logic.weights[0][0] == 0)
  }

  @Test func partialWeightToggleClears() {
    var grid = empty
    grid[3][4] = 0.5
    var logic = RangePainterLogic(weights: grid)
    logic.toggle(row: 3, column: 4)
    #expect(logic.weights[3][4] == 0)
  }

  @Test func dragPaintsFirstCellValue() {
    var grid = empty
    grid[0][1] = 1
    var logic = RangePainterLogic(weights: grid)
    logic.beginStroke(row: 0, column: 0)
    logic.continueStroke(row: 0, column: 1)
    logic.continueStroke(row: 0, column: 2)
    #expect(logic.weights[0][0...2] == [1, 1, 1])
    logic.endStroke()
    logic.beginStroke(row: 0, column: 0)
    logic.continueStroke(row: 0, column: 1)
    #expect(logic.weights[0][0...1] == [0, 0])
  }

  @Test func outOfRangeIgnored() {
    var logic = RangePainterLogic(weights: empty)
    #expect(logic.toggle(row: 13, column: 0) == nil)
    logic.continueStroke(row: 0, column: 0)
    #expect(logic.weights == empty)
  }

  @Test func cellHitTest() {
    let hit = RangePainterLogic.cell(at: CGPoint(x: 45, y: 23), cellSize: 22)
    #expect(hit?.row == 1 && hit?.column == 2)
    #expect(RangePainterLogic.cell(at: CGPoint(x: -1, y: 5), cellSize: 22) == nil)
    #expect(RangePainterLogic.cell(at: CGPoint(x: 22 * 13, y: 5), cellSize: 22) == nil)
  }

  @Test func shortGridIsPadded() {
    let logic = RangePainterLogic(weights: [[1]])
    #expect(logic.weights.count == 13 && logic.weights[12].count == 13 && logic.weights[0][0] == 1)
  }
}
