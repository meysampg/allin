import Foundation

/// A usage or input error: `main.swift` prints it and exits with status 64.
struct ToolError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

/// Writes one line to standard error.
func printError(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Prints the standard "not yet implemented" message and returns exit status 2.
func notImplemented(_ name: String) -> Int32 {
  printError("allin-tool \(name): not yet implemented")
  return 2
}

/// Minimal parser for `--key value`, `--key=value`, boolean `--flag` options and positional arguments.
struct ToolArguments {
  private(set) var values: [String: String] = [:]
  private(set) var flags: Set<String> = []
  private(set) var positional: [String] = []

  /// - Parameter booleanFlags: option names (without `--`) that take no value.
  init(_ args: [String], booleanFlags: Set<String> = []) throws {
    var i = 0
    while i < args.count {
      let arg = args[i]
      i += 1
      guard arg.hasPrefix("--") else {
        positional.append(arg)
        continue
      }
      let body = String(arg.dropFirst(2))
      if let eq = body.firstIndex(of: "=") {
        values[String(body[..<eq])] = String(body[body.index(after: eq)...])
      } else if booleanFlags.contains(body) {
        flags.insert(body)
      } else {
        guard i < args.count else { throw ToolError("missing value for --\(body)") }
        values[body] = args[i]
        i += 1
      }
    }
  }

  func has(_ flag: String) -> Bool { flags.contains(flag) }

  func string(_ key: String) -> String? { values[key] }

  func int(_ key: String, default fallback: Int) throws -> Int {
    guard let raw = values[key] else { return fallback }
    guard let value = Int(raw) else { throw ToolError("--\(key) expects an integer, got '\(raw)'") }
    return value
  }

  func uint64(_ key: String, default fallback: UInt64) throws -> UInt64 {
    guard let raw = values[key] else { return fallback }
    guard let value = UInt64(raw) else { throw ToolError("--\(key) expects an unsigned integer, got '\(raw)'") }
    return value
  }

  func double(_ key: String, default fallback: Double) throws -> Double {
    guard let raw = values[key] else { return fallback }
    guard let value = Double(raw) else { throw ToolError("--\(key) expects a number, got '\(raw)'") }
    return value
  }
}
