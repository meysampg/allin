import XCTest

extension XCUIApplication {
  @MainActor static func allIn(screen: String? = nil, seed: Int = 7, fast: Bool = true, extra: [String] = [])
    -> XCUIApplication
  {
    let app = XCUIApplication()
    var args = ["-AllInDemo", "YES"]
    if let screen { args += ["-AllInScreen", screen] }
    args += ["-AllInSeed", String(seed)]
    if fast { args += ["-AllInFast", "YES"] }
    app.launchArguments = args + extra
    return app
  }
}

@MainActor func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
  app.descendants(matching: .any)[id].firstMatch
}
