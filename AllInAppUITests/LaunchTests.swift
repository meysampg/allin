import XCTest

final class LaunchTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunchShowsTitle() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(element(app, "menu.title").waitForExistence(timeout: 10))
  }
}
