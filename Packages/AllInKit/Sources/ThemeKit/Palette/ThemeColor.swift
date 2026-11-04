import CoreGraphics
import Foundation

/// An sRGB color with components in 0...1. Codable as "#RRGGBB" or "#RRGGBBAA".
public struct ThemeColor: Sendable, Hashable, Codable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// Parses "#RGB", "#RRGGBB" or "#RRGGBBAA" (the leading "#" is optional).
  public init?(hex: String) {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
    if text.count == 3 {
      text = text.map { "\($0)\($0)" }.joined()
    }
    guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
    if text.count == 6 {
      self.init(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255)
    } else {
      self.init(
        red: Double((value >> 24) & 0xFF) / 255,
        green: Double((value >> 16) & 0xFF) / 255,
        blue: Double((value >> 8) & 0xFF) / 255,
        alpha: Double(value & 0xFF) / 255)
    }
  }

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard let color = ThemeColor(hex: text) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "invalid color '\(text)'"))
    }
    self = color
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(hex)
  }

  /// "#RRGGBB", or 8 digits when alpha < 1. Uppercase.
  public var hex: String {
    func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    return alpha < 1 ? base + String(format: "%02X", byte(alpha)) : base
  }

  public var cgColor: CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }

  /// WCAG 2.x relative luminance.
  public var relativeLuminance: Double {
    func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
  }

  /// (L1 + 0.05) / (L2 + 0.05) with L1 the lighter luminance.
  public static func contrastRatio(_ a: ThemeColor, _ b: ThemeColor) -> Double {
    let la = a.relativeLuminance
    let lb = b.relativeLuminance
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }

  /// Euclidean distance in sRGB (components 0...1).
  func distance(to other: ThemeColor) -> Double {
    let dr = red - other.red
    let dg = green - other.green
    let db = blue - other.blue
    return (dr * dr + dg * dg + db * db).squareRoot()
  }
}
