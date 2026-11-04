import XCTest

final class MenuLobbyTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testMenuElements() {
    let app = XCUIApplication.allIn(screen: "menu")
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(element(app, "menu.title").waitForExistence(timeout: 10))
    let ids = [
      "menu.subtitle", "menu.continueCareer", "menu.quickPlay", "menu.gym", "menu.rivals", "menu.myGame",
      "menu.settings", "menu.today", "menu.today.startWarmup", "menu.profile", "menu.background",
    ]
    for id in ids {
      XCTAssertTrue(element(app, id).waitForExistence(timeout: 5), id)
    }
    XCTAssertTrue(app.staticTexts["ALL-IN"].exists)
  }

  @MainActor
  func testLobbyElementsAndDisabledFormats() {
    let app = XCUIApplication.allIn(screen: "lobby")
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(element(app, "lobby.title").waitForExistence(timeout: 10))
    let formats = ["cash6Max", "fullRing", "headsUp", "sitAndGo", "tournament"]
    for id in formats {
      XCTAssertTrue(element(app, "lobby.format.\(id)").waitForExistence(timeout: 5), id)
    }
    XCTAssertFalse(element(app, "lobby.format.fullRing").isEnabled)
    XCTAssertFalse(element(app, "lobby.format.sitAndGo").isEnabled)
    XCTAssertFalse(element(app, "lobby.format.tournament").isEnabled)
    XCTAssertTrue(element(app, "lobby.format.headsUp").isEnabled)
    for id in ["grumli", "zib", "vexa", "mott", "oryn", "random"] {
      XCTAssertTrue(element(app, "lobby.opponent.\(id)").exists, id)
    }
    var options = ["lobby.strength", "lobby.option.stakes", "lobby.sitDown", "lobby.back"]
    options += ["questions", "review", "off"].map { "lobby.option.coach.\($0)" }
    options += ["off", "basic", "full"].map { "lobby.option.hud.\($0)" }
    options += ["relaxed", "normal", "turbo"].map { "lobby.option.speed.\($0)" }
    for id in options {
      XCTAssertTrue(element(app, id).exists, id)
    }
  }

  @MainActor
  func testHeadsUpSitDown() {
    let app = XCUIApplication.allIn(screen: "lobby")
    app.launch()
    defer { app.terminate() }
    let headsUp = element(app, "lobby.format.headsUp")
    XCTAssertTrue(headsUp.waitForExistence(timeout: 10))
    headsUp.click()
    element(app, "lobby.opponent.vexa").click()
    element(app, "lobby.sitDown").click()
    XCTAssertTrue(element(app, "screen.table").waitForExistence(timeout: 10))
    let format = element(app, "table.format")
    if format.waitForExistence(timeout: 5) {
      XCTAssertTrue(format.label.contains("Heads-Up"), format.label)
    }
  }
}
