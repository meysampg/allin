import Foundation

/// Screenshot helper: `-AllInCoachRange YES` (demo mode only) opens the range panel at the first hero decision.
enum CoachDemoFlags {
  static func opensRangeAtFirstDecision(isDemo: Bool) -> Bool {
    isDemo && UserDefaults.standard.bool(forKey: "AllInCoachRange")
  }
}
