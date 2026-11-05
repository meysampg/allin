import AppKit
import SwiftUI

/// Makes sure the app comes to the front when started without activation (UI tests, `open -g`);
/// a background-launched SwiftUI app otherwise never creates its window.
final class AllInAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    // A launch without the "open application" Apple event (XCUITest, `open -g`) leaves SwiftUI with
    // no window; a reopen request makes it present the main scene.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      if NSApp.windows.allSatisfy({ !$0.isVisible }) {
        NSWorkspace.shared.open(Bundle.main.bundleURL)
      }
    }
  }
}

@main
struct AllInApp: App {
  @NSApplicationDelegateAdaptor(AllInAppDelegate.self) private var delegate
  @State private var model = AppModel(launch: .current)

  var body: some Scene {
    Window("All-In", id: "main") {
      RootView()
        .environment(model)
        .frame(minWidth: 1120, minHeight: 700)
    }
    .defaultSize(width: 1120, height: 700)
    .defaultLaunchBehavior(.presented)
    .restorationBehavior(.disabled)
    .commands { AllInCommands() }
  }
}
