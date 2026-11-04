import SwiftUI

@main
struct AllInApp: App {
  @State private var model = AppModel(launch: .current)

  var body: some Scene {
    WindowGroup("All-In") {
      RootView()
        .environment(model)
        .frame(minWidth: 1120, minHeight: 700)
    }
    .defaultSize(width: 1120, height: 700)
    .commands { AllInCommands() }
  }
}
