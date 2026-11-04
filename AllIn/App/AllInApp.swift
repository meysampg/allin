import SwiftUI

@main
struct AllInApp: App {
  var body: some Scene {
    WindowGroup("All-In") {
      RootView()
        .frame(minWidth: 1120, minHeight: 700)
    }
    .defaultSize(width: 1120, height: 700)
  }
}
