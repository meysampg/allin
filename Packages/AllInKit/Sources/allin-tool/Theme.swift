import Foundation

/// `allin-tool theme <validate|render-cards|render-table>`
enum ThemeCommand {
  static let usage = """
    USAGE: allin-tool theme <subcommand> [options]

    SUBCOMMANDS:
      validate [path...]   check theme packs (default: Themes)
      render-cards         render card images from a theme
      render-table         render table images from a theme

    OPTIONS:
      -h, --help           show this help
    """

  static func run(_ args: [String]) async throws -> Int32 {
    guard let sub = args.first else {
      printError(usage)
      return 64
    }
    let rest = Array(args.dropFirst())
    switch sub {
    case "-h", "--help", "help":
      print(usage)
      return 0
    case "validate": return try await ThemeValidateCommand.run(rest)
    case "render-cards": return try await ThemeRenderCardsCommand.run(rest)
    case "render-table": return try await ThemeRenderTableCommand.run(rest)
    default:
      printError("allin-tool theme: unknown subcommand '\(sub)'")
      printError(usage)
      return 64
    }
  }
}
