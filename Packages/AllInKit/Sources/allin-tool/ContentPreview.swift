import Curriculum
import Foundation

enum ContentPreviewCommand {
  static let usage = """
    USAGE: allin-tool content preview <template-id> [--root DIR] [--characters DIR] [--n 8] [--seed 1]

    Prints n generated spots: seed, hash, table, cards, betting line, prompt, answer and the EV list.
    The output is the same for the same template, seed and count.
    """

  static func run(_ args: [String]) async throws -> Int32 {
    if args.contains("-h") || args.contains("--help") {
      print(usage)
      return 0
    }
    let arguments = try ToolArguments(args)
    guard let id = arguments.positional.first else { throw ToolError("missing template id") }
    if arguments.positional.count > 1 { throw ToolError("unexpected argument '\(arguments.positional[1])'") }
    let count = try arguments.int("n", default: 8)
    guard count > 0 else { throw ToolError("--n must be at least 1") }
    let seed = try arguments.uint64("seed", default: 1)
    let library: ContentLibrary
    do { library = try ContentCommand.load(arguments) } catch is ToolFailure { return 1 }
    guard library.template(id) != nil else { throw ToolError("unknown template '\(id)'") }
    for line in try ContentPreviewFormatter.render(library: library, templateID: id, count: count, seed: seed) {
      print(line)
    }
    return 0
  }
}
