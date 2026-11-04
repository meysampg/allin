import Foundation

/// Launch arguments for screenshots and UI tests. Read from `UserDefaults` (command-line `-Key value` pairs).
struct DebugLaunch: Sendable {
  let isDemo: Bool
  let screen: Screen?
  let seed: UInt64?
  let contentDirectory: URL?
  let fast: Bool
  let reduceMotion: Bool

  init(defaults: UserDefaults = .standard) {
    isDemo = defaults.bool(forKey: "AllInDemo")
    screen = defaults.string(forKey: "AllInScreen").flatMap { Screen(rawValue: $0) }
    seed = defaults.string(forKey: "AllInSeed").flatMap { UInt64($0) }
    contentDirectory = defaults.string(forKey: "AllInContent").map { URL(fileURLWithPath: $0, isDirectory: true) }
    fast = defaults.bool(forKey: "AllInFast")
    reduceMotion = defaults.bool(forKey: "AllInReduceMotion")
  }

  static let current = DebugLaunch()
}
