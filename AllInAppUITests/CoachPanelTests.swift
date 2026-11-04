import XCTest

final class CoachPanelTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testShowRangeToggles() {
    let app = XCUIApplication.allIn(screen: "table")
    app.launch()
    XCTAssertTrue(element(app, "table.scene").waitForExistence(timeout: 15))
    let checkCall = element(app, "table.action.checkCall")
    let deadline = Date().addingTimeInterval(60)
    while Date() < deadline, !(checkCall.exists && checkCall.isEnabled) {
      Thread.sleep(forTimeInterval: 0.3)
    }
    XCTAssertTrue(checkCall.exists && checkCall.isEnabled, "no hero decision within 60 s")

    let showRange = element(app, "table.coachBox.showRange")
    XCTAssertTrue(showRange.waitForExistence(timeout: 5))
    if showRange.isEnabled {
      showRange.click()
      let panel = element(app, "table.coachRange")
      XCTAssertTrue(panel.waitForExistence(timeout: 30))
      XCTAssertTrue(element(app, "table.coachRange.title").waitForExistence(timeout: 30))
      let close = element(app, "table.coachRange.close")
      close.click()
      let gone = NSPredicate(format: "exists == false")
      expectation(for: gone, evaluatedWith: panel)
      waitForExpectations(timeout: 10)
    }

    let dismiss = element(app, "table.coachBox.dismiss")
    dismiss.click()
    let box = element(app, "table.coachBox")
    let gone = NSPredicate(format: "exists == false")
    expectation(for: gone, evaluatedWith: box)
    waitForExpectations(timeout: 10)
  }

  @MainActor
  func testHintKeyOpensCoach() {
    let app = XCUIApplication.allIn(screen: "table")
    app.launch()
    XCTAssertTrue(element(app, "table.scene").waitForExistence(timeout: 15))
    let dismiss = element(app, "table.coachBox.dismiss")
    XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
    dismiss.click()
    XCTAssertFalse(element(app, "table.coachBox").waitForExistence(timeout: 2))
    app.typeKey("h", modifierFlags: [])
    XCTAssertTrue(element(app, "table.coachBox").waitForExistence(timeout: 5))
  }
}
