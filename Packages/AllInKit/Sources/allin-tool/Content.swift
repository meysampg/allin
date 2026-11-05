import Curriculum
import Foundation

/// `allin-tool content validate|preview|stats`.
enum ContentCommand {
  static let usage = """
    USAGE: allin-tool content <subcommand> [options]

    SUBCOMMANDS:
      validate   check references, graphs and text, then generate and solve every template
      preview    print generated spots of one template
      stats      count templates, skills, methods and venue content

    Run `allin-tool content <subcommand> --help` for options.
    """

  static func run(_ args: [String]) async throws -> Int32 {
    guard let sub = args.first else {
      print(usage)
      return 64
    }
    if sub == "-h" || sub == "--help" || sub == "help" {
      print(usage)
      return 0
    }
    let rest = Array(args.dropFirst())
    switch sub {
    case "validate": return try await ContentValidateCommand.run(rest)
    case "preview": return try await ContentPreviewCommand.run(rest)
    case "stats": return try await ContentStatsCommand.run(rest)
    default: throw ToolError("unknown subcommand '\(sub)' (expected validate|preview|stats)")
    }
  }

  /// Loads the library named by `--root`/`--characters`. Without `--root`: `Content/` when it has a realm.json, else the
  /// fixture pack.
  static func load(_ arguments: ToolArguments) throws -> ContentLibrary {
    let root: URL
    if let path = arguments.string("root") {
      root = URL(fileURLWithPath: path)
      guard ContentLibrary.hasCurriculum(at: root) else { throw ToolError("no realm.json in '\(path)'") }
    } else {
      let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "Content")
      let content = ContentLibrary.hasCurriculum(at: local) ? local : ContentLibrary.sourceTreeRoot
      if ContentLibrary.hasCurriculum(at: content) {
        root = content
      } else {
        print("no curriculum in Content/ yet; validating fixtures")
        let fixtures = content.appending(path: "fixtures/sample")
        root = ContentLibrary.hasCurriculum(at: fixtures) ? fixtures : ContentLibrary.fixtureRoot
      }
    }
    let characters = arguments.string("characters").map { URL(fileURLWithPath: $0) }
    do {
      return try ContentLibrary.load(root: root, charactersDirectory: characters)
    } catch let error as ContentLoadError {
      for issue in error.issues { printError(issue.description) }
      throw ToolFailure()
    }
  }
}

/// Thrown after the problem was already printed: exit status 1.
struct ToolFailure: Error {}
