import Curriculum
import Foundation

enum ContentValidateCommand {
  static let usage = """
    USAGE: allin-tool content validate [--root DIR] [--characters DIR] [--n 500] [--ev-n 100] [--seed 1]
                                       [--template ID]... [--quick] [--budget validation|test]

    Without --root: Content/ when it has a realm.json, else the fixture pack.
    Prints issues (error: ...) and one line per template. Exit status: 0 no errors, 1 errors, 64 usage.
    """

  static func run(_ args: [String]) async throws -> Int32 {
    if args.contains("-h") || args.contains("--help") {
      print(usage)
      return 0
    }
    // `--template` may repeat, which `ToolArguments` does not keep: collect it first.
    var templates = Set<String>()
    var rest: [String] = []
    var i = 0
    while i < args.count {
      if args[i] == "--template", i + 1 < args.count {
        templates.insert(args[i + 1])
        i += 2
      } else if args[i].hasPrefix("--template=") {
        templates.insert(String(args[i].dropFirst("--template=".count)))
        i += 1
      } else {
        rest.append(args[i])
        i += 1
      }
    }
    let arguments = try ToolArguments(rest, booleanFlags: ["quick"])
    if let extra = arguments.positional.first { throw ToolError("unexpected argument '\(extra)'") }
    var options = arguments.has("quick") ? ValidationOptions.quick : ValidationOptions()
    options.instances = try arguments.int("n", default: options.instances)
    options.evInstances = try arguments.int("ev-n", default: options.evInstances)
    options.seed = try arguments.uint64("seed", default: options.seed)
    if !templates.isEmpty { options.templates = templates }
    switch arguments.string("budget") ?? "validation" {
    case "validation": break
    case "test": options.budget = .test
    case let other: throw ToolError("--budget expects validation or test, got '\(other)'")
    }

    let library: ContentLibrary
    do { library = try ContentCommand.load(arguments) } catch is ToolFailure { return 1 }
    if let wanted = options.templates {
      let unknown = wanted.filter { library.template($0) == nil }.sorted()
      if let first = unknown.first { throw ToolError("unknown template '\(first)'") }
    }
    let clock = ContinuousClock()
    let start = clock.now
    let report = await ContentValidator.validate(library, options: options)
    for issue in report.issues { (issue.severity == .error ? printError : { print($0) })(issue.description) }
    for template in report.templates { print(template.line) }
    let seconds = Double(start.duration(to: clock.now).components.seconds)
    print(
      "\(report.templates.count) template(s), \(report.errors.count) error(s), \(report.warnings.count) warning(s) in \(Int(seconds)) s"
    )
    return report.hasErrors ? 1 : 0
  }
}
