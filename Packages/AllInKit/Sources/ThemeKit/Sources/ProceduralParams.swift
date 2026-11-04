import Foundation

/// A JSON scalar.
public enum ParamValue: Sendable, Hashable, Codable {
  case number(Double)
  case string(String)
  case bool(Bool)

  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let b = try? c.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? c.decode(Double.self) {
      self = .number(n)
    } else if let s = try? c.decode(String.self) {
      self = .string(s)
    } else {
      throw DecodingError.dataCorruptedError(in: c, debugDescription: "expected a number, string or bool")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .number(let n): try c.encode(n)
    case .string(let s): try c.encode(s)
    case .bool(let b): try c.encode(b)
    }
  }
}

public struct ProceduralParams: Sendable, Hashable, Codable, ExpressibleByDictionaryLiteral {
  public var values: [String: ParamValue]

  public init(_ values: [String: ParamValue] = [:]) { self.values = values }

  public init(dictionaryLiteral elements: (String, ParamValue)...) {
    values = Dictionary(elements, uniquingKeysWith: { _, new in new })
  }

  public init(from decoder: any Decoder) throws {
    values = try decoder.singleValueContainer().decode([String: ParamValue].self)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(values)
  }

  public func double(_ key: String, default d: Double) -> Double {
    if case .number(let n)? = values[key] { return n }
    return d
  }

  public func string(_ key: String, default d: String) -> String {
    if case .string(let s)? = values[key] { return s }
    return d
  }

  public func bool(_ key: String, default d: Bool) -> Bool {
    if case .bool(let b)? = values[key] { return b }
    return d
  }

  public func color(_ key: String, default d: ThemeColor) -> ThemeColor {
    if case .string(let s)? = values[key], let c = ThemeColor(hex: s) { return c }
    return d
  }
}

extension ParamValue: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral,
  ExpressibleByBooleanLiteral
{
  public init(floatLiteral value: Double) { self = .number(value) }
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(stringLiteral value: String) { self = .string(value) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}
