import Foundation
import PokerCore
import PokerEquity

/// Decodes one content file into a model value, turning every problem into a `ContentIssue`.
enum ContentDecoding {
  static func decode<T: Decodable>(
    _ type: T.Type, kind: ContentFileKind, data: Data, file: String, issues: inout [ContentIssue]
  ) -> T? {
    let tree: Any
    do {
      tree = try JSONSerialization.jsonObject(with: data)
    } catch {
      issues.append(issue(file: file, code: "json.decode", message: "invalid JSON: \(describe(error))"))
      return nil
    }
    guard let root = tree as? [String: Any] else {
      issues.append(issue(file: file, code: "json.decode", message: "expected Object"))
      return nil
    }
    if let version = root["schemaVersion"] as? Int, version != ContentSchema.version {
      issues.append(
        issue(
          file: file, code: "schema.version",
          message: "schemaVersion \(version) is not supported (expected \(ContentSchema.version))"))
      return nil
    }
    let unknown = kind.schema.unknownKeys(in: root)
    for item in unknown {
      issues.append(issue(file: file, code: "json.unknownKey", path: item.path, message: item.message))
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch let failure as DecodingError {
      issues.append(translate(failure, file: file))
    } catch let failure {
      issues.append(issue(file: file, code: "json.decode", message: "\(failure)"))
    }
    return nil
  }

  private static func issue(file: String, code: String, path: String = "", message: String) -> ContentIssue {
    ContentIssue(.error, code: code, file: file, path: path, message: message)
  }

  private static func describe(_ error: Error) -> String {
    let text = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
    return text ?? error.localizedDescription
  }

  /// `a.b[2]`.
  static func pathString(_ codingPath: [CodingKey]) -> String {
    var text = ""
    for key in codingPath {
      if let index = key.intValue {
        text += "[\(index)]"
      } else {
        text += text.isEmpty ? key.stringValue : ".\(key.stringValue)"
      }
    }
    return text
  }

  private static let stdlibEnums: [String: [String]] = [
    "Street": Street.allCases.map(\.rawValue),
    "StrengthBucket": StrengthBucket.allCases.map(\.rawValue),
  ]

  static func translate(_ failure: DecodingError, file: String) -> ContentIssue {
    switch failure {
    case .keyNotFound(let key, let context):
      return issue(
        file: file, code: "json.decode", path: pathString(context.codingPath),
        message: "missing key '\(key.stringValue)'")
    case .typeMismatch(let type, let context):
      return issue(
        file: file, code: "json.decode", path: pathString(context.codingPath), message: "expected \(name(of: type))")
    case .valueNotFound(let type, let context):
      return issue(
        file: file, code: "json.decode", path: pathString(context.codingPath),
        message: "expected \(name(of: type)), found null")
    case .dataCorrupted(let context):
      var message = context.debugDescription
      var code = "json.decode"
      if message.hasPrefix("bad range") { code = "template.range" }
      let prefix = "Cannot initialize "
      if message.hasPrefix(prefix), let found = message.range(of: " from invalid String value ") {
        let typeName = String(message[message.index(message.startIndex, offsetBy: prefix.count)..<found.lowerBound])
        let value = String(message[found.upperBound...])
        if let allowed = stdlibEnums[typeName] {
          message = "unknown value '\(value)' (expected \(allowed.joined(separator: "|")))"
        }
      }
      return issue(file: file, code: code, path: pathString(context.codingPath), message: message)
    @unknown default:
      return issue(file: file, code: "json.decode", message: "\(failure)")
    }
  }

  private static func name(of type: Any.Type) -> String {
    let text = String(describing: type)
    if text.hasPrefix("Dictionary") { return "Object" }
    if text.hasPrefix("Array") { return "Array" }
    if text == "Double" || text == "Float" { return "Number" }
    return text
  }
}
