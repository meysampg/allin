import Foundation

// allin-tool content | theme | sim | gen-preflop | hh   (see PLAN §10)

let commands: [(name: String, summary: String)] = [
  ("content", "validate and inspect curriculum content"),
  ("theme", "validate theme packs"),
  ("sim", "run bot-vs-bot simulations"),
  ("gen-preflop", "generate the preflop equity table"),
  ("hh", "print or convert hand histories"),
]

func printHelp() {
  print("USAGE: allin-tool <command> [options]\n")
  print("COMMANDS:")
  for c in commands {
    print("  \(c.name.padding(toLength: 12, withPad: " ", startingAt: 0))\(c.summary) (not yet implemented)")
  }
  print("\nOPTIONS:\n  -h, --help    show this help")
}

let args = CommandLine.arguments.dropFirst()
guard let first = args.first else {
  printHelp()
  exit(0)
}
if first == "--help" || first == "-h" || first == "help" {
  printHelp()
  exit(0)
}
if commands.contains(where: { $0.name == first }) {
  FileHandle.standardError.write(Data("allin-tool \(first): not yet implemented\n".utf8))
  exit(2)
}
FileHandle.standardError.write(Data("allin-tool: unknown command '\(first)'\n".utf8))
printHelp()
exit(64)
