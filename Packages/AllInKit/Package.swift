// swift-tools-version: 6.2
import PackageDescription

// Engine modules (PokerCore ... Curriculum) never import SwiftUI, AppKit, SpriteKit or SwiftData.
// Left out until M10 (PLAN 1.1): PokerAbstraction, Solver, and the allin-solve executable.
let package = Package(
  name: "AllInKit",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "PokerCore", targets: ["PokerCore"]),
    .library(name: "PokerEquity", targets: ["PokerEquity"]),
    .library(name: "PokerHost", targets: ["PokerHost"]),
    .library(name: "PokerAI", targets: ["PokerAI"]),
    .library(name: "PokerAnalysis", targets: ["PokerAnalysis"]),
    .library(name: "Curriculum", targets: ["Curriculum"]),
    .library(name: "ThemeKit", targets: ["ThemeKit"]),
    .library(name: "TableKit", targets: ["TableKit"]),
    .library(name: "AllInUI", targets: ["AllInUI"]),
    .library(name: "AllInStore", targets: ["AllInStore"]),
    .executable(name: "allin-tool", targets: ["allin-tool"]),
  ],
  targets: [
    // Engine (portable, no UI frameworks).
    .target(name: "PokerCore"),
    // Resources/ holds preflop169.bin (M2.6). Loaded through Bundle.module, which SwiftPM also generates on Linux.
    .target(name: "PokerEquity", dependencies: ["PokerCore"], resources: [.copy("Resources")]),
    .target(name: "PokerHost", dependencies: ["PokerCore"]),
    .target(name: "PokerAI", dependencies: ["PokerCore", "PokerEquity"]),
    .target(name: "PokerAnalysis", dependencies: ["PokerCore", "PokerEquity", "PokerAI"]),
    .target(
      name: "Curriculum",
      dependencies: ["PokerCore", "PokerEquity", "PokerAI", "PokerAnalysis"]),
    // Presentation and persistence (may use Apple frameworks).
    .target(name: "ThemeKit"),
    .target(name: "TableKit", dependencies: ["ThemeKit", "PokerCore"], resources: [.copy("Shaders")]),
    .target(name: "AllInUI", dependencies: ["ThemeKit", "PokerCore", "PokerEquity"]),
    .target(name: "AllInStore", dependencies: ["Curriculum", "PokerAnalysis", "PokerCore"]),
    .executableTarget(
      name: "allin-tool",
      dependencies: ["PokerCore", "PokerEquity", "PokerHost", "PokerAI", "Curriculum", "ThemeKit", "TableKit"]),
    // Tests.
    .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
    .testTarget(name: "PokerEquityTests", dependencies: ["PokerEquity", "PokerCore"]),
    .testTarget(name: "PokerHostTests", dependencies: ["PokerHost", "PokerCore"]),
    // PokerHost only for headless matches in tests; the PokerAI module itself never imports PokerHost.
    .testTarget(name: "PokerAITests", dependencies: ["PokerAI", "PokerCore", "PokerEquity", "PokerHost"]),
    .testTarget(
      name: "PokerAnalysisTests", dependencies: ["PokerAnalysis", "PokerCore", "PokerEquity", "PokerAI"]),
    .testTarget(
      name: "CurriculumTests", dependencies: ["Curriculum", "PokerCore", "PokerEquity", "PokerAI", "PokerAnalysis"]),
    .testTarget(name: "ThemeKitTests", dependencies: ["ThemeKit"]),
    .testTarget(name: "TableKitTests", dependencies: ["TableKit", "ThemeKit", "PokerCore"]),
    .testTarget(name: "AllInUIKitTests", dependencies: ["AllInUI", "ThemeKit", "PokerCore", "PokerEquity"]),
    .testTarget(name: "AllInStoreTests", dependencies: ["AllInStore", "Curriculum", "PokerCore"]),
    // Filtered by name from Tools/test.sh: unit skips Heavy and Sim.
    .testTarget(
      name: "HeavyTests", dependencies: ["PokerCore", "PokerEquity", "PokerAI", "PokerAnalysis", "Curriculum"]),
    .testTarget(
      name: "SimTests", dependencies: ["PokerHost", "PokerAI", "PokerCore", "PokerEquity", "PokerAnalysis"]),
    .testTarget(
      name: "ContentTests", dependencies: ["Curriculum", "PokerCore", "PokerEquity", "PokerAI", "PokerAnalysis"]),
  ]
)
