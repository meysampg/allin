import XCTest

final class TablePlayTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testPlayThreeHandsWithKeyboard() {
    let app = XCUIApplication.allIn(screen: "table")
    app.launch()
    XCTAssertTrue(element(app, "table.scene").waitForExistence(timeout: 15))

    let deadline = Date().addingTimeInterval(180)
    var handsDone = 0
    var decisionsInHand2 = 0
    while Date() < deadline {
      // Key events only reach the app while it is frontmost; reclaim focus if something stole it.
      if app.state != .runningForeground { app.activate() }
      if element(app, "table.nextHand").exists {
        handsDone += 1
        if handsDone == 3 { break }
        app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
        decisionsInHand2 = 0
        Thread.sleep(forTimeInterval: 0.5)
        continue
      }
      let checkCall = element(app, "table.action.checkCall")
      if checkCall.exists, checkCall.isEnabled {
        if handsDone == 1, decisionsInHand2 == 0 {
          decisionsInHand2 += 1
          app.typeKey("r", modifierFlags: [])
          app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
          Thread.sleep(forTimeInterval: 1)
          if checkCall.isEnabled { app.typeKey("c", modifierFlags: []) }
        } else {
          decisionsInHand2 += 1
          app.typeKey("c", modifierFlags: [])
        }
      }
      Thread.sleep(forTimeInterval: 0.2)
    }
    XCTAssertEqual(handsDone, 3)
    XCTAssertTrue(text(of: element(app, "table.handNumber")).contains("3"))
  }

  @MainActor
  func testEscapeOpensTableMenu() {
    let app = XCUIApplication.allIn(screen: "table")
    app.launch()
    XCTAssertTrue(element(app, "table.scene").waitForExistence(timeout: 15))
    app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    let leave = element(app, "table.leave")
    XCTAssertTrue(leave.waitForExistence(timeout: 5))
    leave.click()
    XCTAssertTrue(element(app, "screen.lobby").waitForExistence(timeout: 10))
  }
}
