import Foundation

// allin-tool <command> [options]   (see PLAN §10). Each command lives in its own file and exposes
// `static func run(_ args: [String]) async throws -> Int32`.

let commands: [(name: String, summary: String)] = [
  ("content", "validate and inspect curriculum content"),
  ("theme", "validate theme packs"),
  ("sim", "run bot-vs-bot simulations"),
  ("gen-preflop", "generate the preflop equity table"),
  ("gen-preflop-ranges", "generate BaselineStrategy preflop ranges"),
  ("hh", "print or convert hand histories"),
]

func printHelp() {
  print("USAGE: allin-tool <command> [options]\n")
  print("COMMANDS:")
  for c in commands {
    print("  \(c.name.padding(toLength: 20, withPad: " ", startingAt: 0))\(c.summary)")
  }
  print("\nOPTIONS:\n  -h, --help    show this help")
}

func runCommand(_ name: String, _ rest: [String]) async throws -> Int32 {
  switch name {
  case "sim": return try await SimCommand.run(rest)
  case "gen-preflop": return try await GenPreflopCommand.run(rest)
  case "gen-preflop-ranges": return try await GenPreflopRangesCommand.run(rest)
  default: return notImplemented(name)
  }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first else {
  printHelp()
  exit(0)
}
if first == "--help" || first == "-h" || first == "help" {
  printHelp()
  exit(0)
}
guard commands.contains(where: { $0.name == first }) else {
  printError("allin-tool: unknown command '\(first)'")
  printHelp()
  exit(64)
}
do {
  let status = try await runCommand(first, Array(args.dropFirst()))
  exit(status)
} catch let error as ToolError {
  printError("allin-tool \(first): \(error.description)")
  exit(64)
} catch {
  printError("allin-tool \(first): \(error)")
  exit(1)
}
