import XCTest

final class ExplainSandboxTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testExplainDemoElements() {
    let app = XCUIApplication.allIn(screen: "lesson:3")
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(element(app, "explain.verdict").waitForExistence(timeout: 15))
    for id in [
      "explain.back", "explain.title", "explain.step", "explain.thinking", "explain.explainer.potSlices",
      "explain.explainer.outsGlow", "sandbox.panel", "sandbox.title", "sandbox.heroCards", "sandbox.board",
      "sandbox.bet", "sandbox.bet.value", "sandbox.meter.priceNeeded", "equityBars.price", "sandbox.challenge",
    ] {
      XCTAssertTrue(element(app, id).waitForExistence(timeout: 5), id)
    }
    let chance = element(app, "equityBars.chance")
    XCTAssertTrue(chance.waitForExistence(timeout: 5))
    XCTAssertTrue(
      waitUntil(timeout: 60) { chance.exists && text(of: chance).contains("%") },
      "equity chance never showed a percentage")
    XCTAssertTrue(text(of: element(app, "explain.next")).contains("Next: try 3 spots on your own"))
  }

  @MainActor
  func testBetSliderChangesPrice() {
    let app = XCUIApplication.allIn(screen: "lesson:3")
    app.launch()
    defer { app.terminate() }
    let price = element(app, "equityBars.price")
    XCTAssertTrue(price.waitForExistence(timeout: 15))
    let before = text(of: price)
    let slider = element(app, "sandbox.bet")
    XCTAssertTrue(slider.waitForExistence(timeout: 5))
    slider.adjust(toNormalizedSliderPosition: 0.95)
    XCTAssertTrue(waitUntil(timeout: 60) { price.exists && text(of: price) != before }, "price did not change")
  }

  @MainActor
  func testNextGoesToApply() {
    let app = XCUIApplication.allIn(screen: "lesson:3")
    app.launch()
    defer { app.terminate() }
    let next = element(app, "explain.next")
    XCTAssertTrue(next.waitForExistence(timeout: 15))
    next.click()
    let rep = element(app, "lesson.rep")
    XCTAssertTrue(rep.waitForExistence(timeout: 15))
    XCTAssertTrue(text(of: rep).contains("Spot 1 / 3"))
  }
}
