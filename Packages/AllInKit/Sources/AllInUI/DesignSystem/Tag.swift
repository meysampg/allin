import SwiftUI

public enum TagStyle: Sendable { case plain, gold, good, bad, muted, dark }

public struct Tag: View {
  @Environment(\.theme) private var theme
  private let text: String
  private let systemImage: String?
  private let style: TagStyle

  public init(_ text: String, systemImage: String? = nil, style: TagStyle = .plain) {
    self.text = text
    self.systemImage = systemImage
    self.style = style
  }

  public var body: some View {
    let colors = palette
    HStack(spacing: 4) {
      if let systemImage { Image(systemName: systemImage) }
      Text(text)
    }
    .font(theme.bodyFont(size: 11, weight: .semibold))
    .foregroundStyle(colors.text)
    .padding(.vertical, 3)
    .padding(.horizontal, 9)
    .background(Capsule().fill(colors.fill))
    .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1.5))
    .accessibilityElement(children: .combine)
  }

  private var palette: (fill: Color, text: Color, border: Color) {
    switch style {
    case .plain: return (theme.parchment, theme.ink, theme.ink.opacity(0.6))
    case .gold: return (theme.gold.opacity(0.35), theme.ink, theme.gold)
    case .good: return (theme.good, .white, theme.good)
    case .bad: return (theme.bad, .white, theme.bad)
    case .muted: return (theme.mute.opacity(0.2), theme.mute, theme.mute)
    case .dark: return (theme.ink, theme.parchment, theme.ink)
    }
  }
}
