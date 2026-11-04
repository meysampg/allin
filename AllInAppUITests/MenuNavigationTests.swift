import XCTest

final class MenuNavigationTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testMenuToLobbyAndBack() {
    let app = XCUIApplication()
    app.launch()
    defer { app.terminate() }
    let quickPlay = element(app, "menu.quickPlay")
    XCTAssertTrue(quickPlay.waitForExistence(timeout: 10))
    quickPlay.click()
    XCTAssertTrue(element(app, "screen.lobby").waitForExistence(timeout: 10))
    element(app, "lobby.back").click()
    XCTAssertTrue(element(app, "screen.menu").waitForExistence(timeout: 10))
  }

  @MainActor
  func testDemoLaunchScreens() {
    for id in ["menu", "lobby", "table", "gym", "settings"] {
      let app = XCUIApplication.allIn(screen: id)
      app.launch()
      XCTAssertTrue(element(app, "screen.\(id)").waitForExistence(timeout: 10), "screen.\(id)")
      app.terminate()
    }
  }

  @MainActor
  func testPlaceholderBack() {
    let app = XCUIApplication.allIn(screen: "gym")
    app.launch()
    defer { app.terminate() }
    let back = element(app, "placeholder.back")
    XCTAssertTrue(back.waitForExistence(timeout: 10))
    back.click()
    XCTAssertTrue(element(app, "screen.menu").waitForExistence(timeout: 10))
  }
}
