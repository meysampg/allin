import XCTest

final class CareerVenueTests: XCTestCase {
  private let venueIDs = ["fx.tavern", "fx.guild", "fx.keep", "fx.hoard"]

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testCareerDemoElements() {
    let app = XCUIApplication.allIn(screen: "career")
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(element(app, "screen.career").waitForExistence(timeout: 10))
    for id in ["career.back", "career.title", "career.gold", "career.venueCount", "career.teaches", "career.token"] {
      XCTAssertTrue(element(app, id).waitForExistence(timeout: 5), id)
    }
    for id in venueIDs {
      XCTAssertTrue(element(app, "career.venue.\(id)").exists, id)
      XCTAssertTrue(element(app, "career.teaches.\(id)").exists, id)
    }
    XCTAssertEqual(text(of: element(app, "career.venueCount")), "Venue 1 of 4")
    XCTAssertTrue(text(of: element(app, "career.venue.fx.tavern.status")).contains("3 / 7"))
    XCTAssertTrue(text(of: element(app, "career.venue.fx.guild.status")).contains("beat the Tavern boss"))
  }

  @MainActor
  func testCareerToVenueAndBack() {
    let app = XCUIApplication.allIn(screen: "career")
    app.launch()
    defer { app.terminate() }
    let tavern = element(app, "career.venue.fx.tavern")
    XCTAssertTrue(tavern.waitForExistence(timeout: 10))
    tavern.click()
    XCTAssertTrue(element(app, "screen.venue").waitForExistence(timeout: 10))
    XCTAssertTrue(element(app, "venue.title").waitForExistence(timeout: 5))
    element(app, "venue.back").click()
    XCTAssertTrue(element(app, "screen.career").waitForExistence(timeout: 10))
  }

  @MainActor
  func testVenueDemoElements() {
    let app = XCUIApplication.allIn(screen: "venue")
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(element(app, "screen.venue").waitForExistence(timeout: 10))
    for id in [
      "venue.back", "venue.title", "venue.chapter", "venue.banner", "venue.host", "venue.skills", "venue.skillsNote",
    ] {
      XCTAssertTrue(element(app, id).waitForExistence(timeout: 5), id)
    }
    XCTAssertEqual(text(of: element(app, "venue.host")), "Marta the Innkeeper: Pull up a stool, traveler.")
    for n in 1...7 {
      XCTAssertTrue(element(app, "venue.node.fx.tavern.n\(n)").exists, "n\(n)")
    }
    for n in 1...3 {
      XCTAssertEqual(text(of: element(app, "venue.node.fx.tavern.n\(n).status")), "\u{2713}")
      XCTAssertTrue(element(app, "venue.node.fx.tavern.n\(n).stars").exists, "stars n\(n)")
    }
    XCTAssertEqual(text(of: element(app, "venue.node.fx.tavern.n4.status")), "\u{25CF}")
    XCTAssertTrue(element(app, "venue.node.fx.tavern.n4.play").exists)
    for n in 5...7 {
      XCTAssertEqual(text(of: element(app, "venue.node.fx.tavern.n\(n).status")), "\u{1F512}")
      XCTAssertFalse(element(app, "venue.node.fx.tavern.n\(n).play").exists)
    }
    let meters = ["rules", "ranks", "board", "value"]
    for meter in meters { XCTAssertTrue(element(app, "venue.meter.fx.tavern.\(meter)").exists, meter) }
    XCTAssertEqual(text(of: element(app, "venue.meter.fx.tavern.rules")), "80%")
  }

  @MainActor
  func testMenuContinueCareerOpensMap() {
    let app = XCUIApplication.allIn(screen: "menu")
    app.launch()
    defer { app.terminate() }
    let button = element(app, "menu.continueCareer")
    XCTAssertTrue(button.waitForExistence(timeout: 10))
    button.click()
    XCTAssertTrue(element(app, "screen.career").waitForExistence(timeout: 10))
  }

  @MainActor
  func testVenuePlayOpensLesson() {
    let app = XCUIApplication.allIn(screen: "venue")
    app.launch()
    defer { app.terminate() }
    let play = element(app, "venue.node.fx.tavern.n4.play")
    XCTAssertTrue(play.waitForExistence(timeout: 10))
    play.click()
    XCTAssertTrue(element(app, "screen.lesson").waitForExistence(timeout: 10))
    element(app, "lesson.close").click()
    XCTAssertTrue(element(app, "screen.venue").waitForExistence(timeout: 10))
  }
}
