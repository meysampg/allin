import Foundation

public struct ThemeIssue: Sendable, Hashable, CustomStringConvertible {
  public enum Severity: String, Sendable { case error, warning }

  public enum Code: String, Sendable {
    case unsupportedSchema, unknownSlot, unknownProcedural, kindMismatch, emptySlotEntry
    case unresolvedExtends, extendsCycle, missingFile, badFormat, badSize, badAspect, missingAlpha
    case soundTooLong, musicTooLarge, invalidColor, unknownPaletteKey, lowContrast, suitsNotDistinct
    case missingLicenseField, missingLicenseFile, packTooLarge, unreadableManifest
  }

  public let severity: Severity
  public let code: Code
  public let slotID: String?
  public let message: String

  public init(severity: Severity = .error, code: Code, slotID: String? = nil, message: String) {
    self.severity = severity
    self.code = code
    self.slotID = slotID
    self.message = message
  }

  /// `<severity> <code> [slot] message`
  public var description: String {
    let slot = slotID.map { " [\($0)]" } ?? ""
    return "\(severity.rawValue) \(code.rawValue)\(slot) \(message)"
  }
}

public struct ThemeValidationReport: Sendable {
  public let packID: String?
  public let url: URL
  public let issues: [ThemeIssue]

  public init(packID: String?, url: URL, issues: [ThemeIssue]) {
    self.packID = packID
    self.url = url
    self.issues = issues
  }

  public var errors: [ThemeIssue] { issues.filter { $0.severity == .error } }
  public var isValid: Bool { errors.isEmpty }
}
