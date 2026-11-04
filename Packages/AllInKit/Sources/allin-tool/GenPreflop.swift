import Foundation
import PokerEquity
import Synchronization

/// `allin-tool gen-preflop [--out <path>]`: writes the exact preflop equity table (about 380 KB).
/// Run in release: `swift run -c release --package-path Packages/AllInKit allin-tool gen-preflop`.
enum GenPreflopCommand {
  static let defaultOutput = "Packages/AllInKit/Sources/PokerEquity/Resources/preflop169.bin"

  static func run(_ args: [String]) async throws -> Int32 {
    let parsed = try ToolArguments(args)
    let path = parsed.string("out") ?? defaultOutput
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent().path
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw ToolError("output directory does not exist: \(directory)")
    }
    let milestone = Mutex(0)
    let start = ContinuousClock.now
    let data = await PreflopTableGenerator.generate { fraction in
      let step = Int(fraction * 20)
      let isNew = milestone.withLock { last -> Bool in
        guard step > last else { return false }
        last = step
        return true
      }
      if isNew { print("gen-preflop: \(step * 5)%") }
    }
    let elapsed = ContinuousClock.now - start
    try data.write(to: url, options: .atomic)
    let table = try PreflopEquityTable(data: data)
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let time = String(format: "%.1f", seconds)
    print("gen-preflop: wrote \(path): \(table.entryCount) entries, \(data.count) bytes, \(time) s")
    return 0
  }
}
