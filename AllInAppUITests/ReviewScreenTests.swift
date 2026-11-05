import XCTest

final class ReviewScreenTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testDemoReviewElements() {
    let app = XCUIApplication.allIn(screen: "review")
    app.launch()
    XCTAssertTrue(element(app, "review.decision.0").waitForExistence(timeout: 180), "grading did not finish")
    let ids = [
      "review.back", "review.title", "review.summary", "review.timeline", "review.street.preflop",
      "review.street.flop", "review.street.turn", "review.street.river", "review.table",
      "review.explanation.title", "review.evChart", "review.replaySpot", "review.addToGym", "review.rivalNotes",
      "review.footnote",
    ]
    for id in ids {
      XCTAssertTrue(element(app, id).waitForExistence(timeout: 5), "missing \(id)")
    }
    let before = text(of: element(app, "review.explanation.title"))
    let next = element(app, "review.next")
    let prev = element(app, "review.prev")
    if next.isEnabled {
      next.click()
      XCTAssertNotEqual(text(of: element(app, "review.explanation.title")), before)
      prev.click()
      XCTAssertEqual(text(of: element(app, "review.explanation.title")), before)
    } else if prev.isEnabled {
      prev.click()
      next.click()
      XCTAssertEqual(text(of: element(app, "review.explanation.title")), before)
    }
  }

  @MainActor
  func testLastHandFromTable() {
    let app = XCUIApplication.allIn(screen: "table")
    app.launch()
    XCTAssertTrue(element(app, "table.scene").waitForExistence(timeout: 15))

    let nextHand = element(app, "table.nextHand")
    let checkCall = element(app, "table.action.checkCall")
    let deadline = Date().addingTimeInterval(120)
    while Date() < deadline, !nextHand.exists {
      if app.state != .runningForeground { app.activate() }
      if checkCall.exists, checkCall.isEnabled { app.typeKey("c", modifierFlags: []) }
      Thread.sleep(forTimeInterval: 0.2)
    }
    XCTAssertTrue(nextHand.exists, "the hand did not finish")

    let lastHand = element(app, "table.lastHand")
    let enabled = NSPredicate(format: "isEnabled == true")
    expectation(for: enabled, evaluatedWith: lastHand)
    waitForExpectations(timeout: 15)
    lastHand.click()

    XCTAssertTrue(element(app, "table.review").waitForExistence(timeout: 10))
    let back = element(app, "review.back")
    XCTAssertTrue(back.waitForExistence(timeout: 10))
    back.click()
    XCTAssertTrue(element(app, "table.scene").waitForExistence(timeout: 10))
    XCTAssertTrue(element(app, "table.nextHand").exists)
  }
}
