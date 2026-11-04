import Foundation
import PokerAI

/// `allin-tool gen-preflop-ranges [--out path] [--seed 1] [--samples 1500]`: regenerates the preflop ranges of
/// `BaselineStrategy` and writes `BaselineRanges+Generated.swift` (by default into the source tree).
enum GenPreflopRangesCommand {
  static func run(_ args: [String]) async throws -> Int32 {
    let parsed = try ToolArguments(args)
    let seed = try parsed.uint64("seed", default: 1)
    let samples = try parsed.int("samples", default: 1500)
    guard samples > 0 else { throw ToolError("--samples must be positive") }
    let out = parsed.string("out").map { URL(fileURLWithPath: $0) } ?? defaultOutput
    printError("gen-preflop-ranges: seed \(seed), \(samples) samples per class -> \(out.path)")
    let started = Date()
    let ranges = BaselineRangeModel.generate(seed: seed, samplesPerClass: samples)
    let source = BaselineRangeModel.swiftSource(for: ranges)
    try source.write(to: out, atomically: true, encoding: .utf8)
    let seconds = Date().timeIntervalSince(started)
    printError("gen-preflop-ranges: wrote \(source.utf8.count) bytes in \(String(format: "%.1f", seconds)) s")
    return 0
  }

  /// `Sources/PokerAI/Baseline/BaselineRanges+Generated.swift`, found relative to this source file.
  private static var defaultOutput: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("PokerAI/Baseline/BaselineRanges+Generated.swift")
  }
}
