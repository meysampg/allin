import Foundation

/// Launch arguments for screenshots and UI tests. Read from `UserDefaults` (command-line `-Key value` pairs).
struct DebugLaunch: Sendable {
  let isDemo: Bool
  let screen: Screen?
  /// The part of `-AllInScreen <id>:<arg>` after the first colon.
  let screenArgument: String?
  let seed: UInt64?
  let contentDirectory: URL?
  let fast: Bool
  let reduceMotion: Bool

  init(defaults: UserDefaults = .standard) {
    isDemo = defaults.bool(forKey: "AllInDemo")
    let raw = defaults.string(forKey: "AllInScreen")
    let parts = raw?.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    screen = parts?.first.flatMap { Screen(rawValue: String($0)) }
    screenArgument = parts.flatMap { $0.count > 1 && !$0[1].isEmpty ? String($0[1]) : nil }
    seed = defaults.string(forKey: "AllInSeed").flatMap { UInt64($0) }
    contentDirectory = defaults.string(forKey: "AllInContent").map { URL(fileURLWithPath: $0, isDirectory: true) }
    fast = defaults.bool(forKey: "AllInFast")
    reduceMotion = defaults.bool(forKey: "AllInReduceMotion")
  }

  static let current = DebugLaunch()
}
