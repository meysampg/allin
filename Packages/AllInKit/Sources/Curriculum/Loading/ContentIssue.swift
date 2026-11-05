import Foundation

public enum IssueSeverity: String, Sendable, Codable { case error, warning }

public struct ContentIssue: Error, Sendable, Hashable, CustomStringConvertible {
  public let severity: IssueSeverity
  /// Stable code, for example `ref.unknown`.
  public let code: String
  /// Root-relative file, for example "venues/fx.tavern/spots/potodds-flush-draw.json"; "" for library-wide issues.
  public let file: String
  /// JSON path, for example "question.options[2]"; "" if none.
  public let path: String
  public let message: String

  public init(_ severity: IssueSeverity, code: String, file: String, path: String = "", message: String) {
    self.severity = severity
    self.code = code
    self.file = file
    self.path = path
    self.message = message
  }

  /// "error: <file>: <path>: <message>", empty parts omitted.
  public var description: String {
    "\(severity.rawValue): " + [file, path, message].filter { !$0.isEmpty }.joined(separator: ": ")
  }
}

public struct ContentLoadError: Error, Sendable, CustomStringConvertible {
  public let issues: [ContentIssue]

  public init(issues: [ContentIssue]) { self.issues = issues }

  public var description: String { issues.map(\.description).joined(separator: "\n") }
}
