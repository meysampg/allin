import XCTest

final class LessonPlayTests: XCTestCase {
  /// Spots are solved off the main thread (slowly in a debug build), so waits are generous.
  private let solveTimeout: TimeInterval = 90

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testPuzzleDemoElements() {
    let app = XCUIApplication.allIn(screen: "lesson")
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(element(app, "screen.lesson").waitForExistence(timeout: 10))
    XCTAssertTrue(element(app, "lesson.option.call").waitForExistence(timeout: solveTimeout))
    XCTAssertEqual(text(of: element(app, "lesson.step")), "Step 2 / 5")
    for id in [
      "lesson.close", "lesson.title", "lesson.progress", "lesson.scene", "lesson.coach", "lesson.coach.text",
      "lesson.prompt", "lesson.decisionLabel", "lesson.option.fold", "lesson.option.call", "lesson.hint",
      "lesson.pot",
    ] {
      XCTAssertTrue(element(app, id).exists, id)
    }
    XCTAssertTrue(element(app, "lesson.option.raise-3").exists, "lesson.option.raise-3")
    XCTAssertEqual(text(of: element(app, "lesson.title")), "Pot odds: is the call worth it?")
    XCTAssertEqual(text(of: element(app, "lesson.decisionLabel")), "Your decision:")
    XCTAssertTrue(text(of: element(app, "lesson.hint")).contains("Hint"))
  }

  @MainActor
  func testHintCostsAStar() {
    let app = XCUIApplication.allIn(screen: "lesson")
    app.launch()
    defer { app.terminate() }
    let hint = element(app, "lesson.hint")
    XCTAssertTrue(hint.waitForExistence(timeout: solveTimeout))
    XCTAssertTrue(hint.isEnabled)
    XCTAssertFalse(element(app, "lesson.coach.hint").exists)
    hint.click()
    XCTAssertTrue(element(app, "lesson.coach.hint").waitForExistence(timeout: 5))
    XCTAssertFalse(element(app, "lesson.hint").isEnabled)
  }

  @MainActor
  func testPlayFixtureLessonEndToEnd() {
    let app = XCUIApplication.allIn(screen: "venue")
    app.launch()
    defer { app.terminate() }
    let play = element(app, "venue.node.fx.tavern.n4.play")
    XCTAssertTrue(play.waitForExistence(timeout: 10))
    play.click()
    XCTAssertTrue(element(app, "screen.lesson").waitForExistence(timeout: 10))

    // Step 1: the hook. Step 2: the puzzle.
    for expected in ["Step 1 / 5", "Step 2 / 5"] {
      answer(app, option: "call")
      XCTAssertEqual(text(of: element(app, "lesson.step")), expected)
      next(app)
    }

    // Step 3: explain and sandbox on one page.
    let explainNext = element(app, "explain.next")
    XCTAssertTrue(explainNext.waitForExistence(timeout: solveTimeout))
    XCTAssertEqual(text(of: element(app, "explain.step")), "Step 3 / 5")
    explainNext.click()

    // Step 5: three spots on your own.
    for spot in 1...3 {
      answer(app, option: "call")
      XCTAssertEqual(text(of: element(app, "lesson.step")), "Step 5 / 5")
      XCTAssertEqual(text(of: element(app, "lesson.rep")), "Spot \(spot) / 3")
      next(app)
    }

    XCTAssertTrue(element(app, "lesson.summary").waitForExistence(timeout: 10))
    XCTAssertTrue(element(app, "lesson.summary.stars").exists)
    XCTAssertTrue(element(app, "lesson.summary.apply").exists)
    element(app, "lesson.summary.done").click()
    XCTAssertTrue(element(app, "screen.venue").waitForExistence(timeout: 10))
    XCTAssertTrue(element(app, "venue.node.fx.tavern.n4.stars").waitForExistence(timeout: 5))
    XCTAssertEqual(text(of: element(app, "venue.node.fx.tavern.n4.status")), "\u{2713}")
  }

  @MainActor
  private func answer(_ app: XCUIApplication, option: String) {
    let button = element(app, "lesson.option.\(option)")
    XCTAssertTrue(button.waitForExistence(timeout: solveTimeout), option)
    button.click()
    XCTAssertTrue(element(app, "lesson.verdict").waitForExistence(timeout: 10))
    XCTAssertTrue(element(app, "lesson.verdict.detail").exists)
  }

  @MainActor
  private func next(_ app: XCUIApplication) {
    let button = element(app, "lesson.next")
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    button.click()
  }
}
