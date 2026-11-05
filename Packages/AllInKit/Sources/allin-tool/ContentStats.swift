import Curriculum
import Foundation

enum ContentStatsCommand {
  static let usage = """
    USAGE: allin-tool content stats [--root DIR] [--characters DIR]

    Prints templates per skill, method and question type, a difficulty histogram and per-venue counts.
    """

  static func run(_ args: [String]) async throws -> Int32 {
    if args.contains("-h") || args.contains("--help") {
      print(usage)
      return 0
    }
    let arguments = try ToolArguments(args)
    if let extra = arguments.positional.first { throw ToolError("unexpected argument '\(extra)'") }
    let library: ContentLibrary
    do { library = try ContentCommand.load(arguments) } catch is ToolFailure { return 1 }
    for line in ContentStats(library).lines() { print(line) }
    return 0
  }
}
