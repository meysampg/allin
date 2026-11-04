import SwiftUI

public enum FantasyButtonKind: Sendable { case primary, secondary, small }

public struct FantasyButtonStyle: ButtonStyle {
  private let kind: FantasyButtonKind

  public init(_ kind: FantasyButtonKind = .secondary) {
    self.kind = kind
  }

  public func makeBody(configuration: Configuration) -> some View {
    FantasyButtonBody(kind: kind, configuration: configuration)
  }
}

extension ButtonStyle where Self == FantasyButtonStyle {
  public static func fantasy(_ kind: FantasyButtonKind = .secondary) -> FantasyButtonStyle {
    FantasyButtonStyle(kind)
  }
}

private struct FantasyButtonBody: View {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled
  let kind: FantasyButtonKind
  let configuration: ButtonStyle.Configuration

  var body: some View {
    let small = kind == .small
    let radius: CGFloat = small ? 8 : 12
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    configuration.label
      .font(theme.bodyFont(size: small ? 12 : 15, weight: .semibold))
      .foregroundStyle(kind == .primary ? theme.parchment : theme.ink)
      .padding(.vertical, small ? 4 : 9)
      .padding(.horizontal, small ? 10 : 18)
      .background(shape.fill(kind == .primary ? theme.ink : theme.parchment))
      .overlay(shape.strokeBorder(theme.gold, lineWidth: 2))
      .contentShape(shape)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(isEnabled ? 1 : 0.45)
  }
}
