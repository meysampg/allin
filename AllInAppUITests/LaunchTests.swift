import XCTest

final class LaunchTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunchShowsTitle() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.staticTexts["ALL-IN"].waitForExistence(timeout: 10))
  }
}
