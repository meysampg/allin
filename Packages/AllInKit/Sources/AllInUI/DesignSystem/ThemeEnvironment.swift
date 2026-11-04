import SwiftUI

extension EnvironmentValues {
  @Entry public var theme: Theme = .hearthwood
}

extension View {
  /// Injects `theme` into the environment and tints controls with its gold.
  public func allInTheme(_ theme: Theme) -> some View {
    environment(\.theme, theme).tint(theme.gold)
  }
}
