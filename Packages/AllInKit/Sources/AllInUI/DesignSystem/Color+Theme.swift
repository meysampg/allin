import SwiftUI
import ThemeKit

extension Color {
  /// Creates an sRGB SwiftUI color from a theme color.
  public init(_ themeColor: ThemeColor) {
    self.init(
      .sRGB, red: themeColor.red, green: themeColor.green, blue: themeColor.blue, opacity: themeColor.alpha)
  }
}
