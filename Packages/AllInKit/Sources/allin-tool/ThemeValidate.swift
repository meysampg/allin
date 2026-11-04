import Foundation
import ThemeKit

/// `allin-tool theme validate [path...]`: each path is a `.allintheme` folder or a folder of packs.
enum ThemeValidateCommand {
  static let usage = """
    USAGE: allin-tool theme validate [path...]

    Each path is a .allintheme folder or a folder of packs (default: Themes).
    Prints "<pack>: <severity> <code> [slot] message" per issue.
    Exit status: 0 no errors, 1 errors found, 64 usage error.
    """

  static func run(_ args: [String]) async throws -> Int32 {
    if args.contains("-h") || args.contains("--help") {
      print(usage)
      return 0
    }
    if let flag = args.first(where: { $0.hasPrefix("-") }) { throw ToolError("unknown option '\(flag)'") }
    let paths = args.isEmpty ? ["Themes"] : args
    var reports: [ThemeValidationReport] = []
    for path in paths {
      let url = URL(fileURLWithPath: path)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw ToolError("'\(path)' is not a directory")
      }
      if url.pathExtension == "allintheme" {
        reports.append(ThemeValidator.validate(packAt: url))
      } else {
        reports += ThemeValidator.validateAll(in: url)
      }
    }
    var errorCount = 0
    var warningCount = 0
    for report in reports {
      let name = report.packID ?? report.url.lastPathComponent
      for issue in report.issues { print("\(name): \(issue)") }
      errorCount += report.errors.count
      warningCount += report.issues.count - report.errors.count
      if report.issues.isEmpty { print("\(name): ok") }
    }
    print("\(reports.count) pack(s), \(errorCount) error(s), \(warningCount) warning(s)")
    return errorCount == 0 ? 0 : 1
  }
}
