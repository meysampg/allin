import SwiftUI

public struct ParchmentPanel<Content: View>: View {
  @Environment(\.theme) private var theme
  private let title: String?
  private let padding: CGFloat
  private let content: Content

  public init(title: String? = nil, padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
    self.title = title
    self.padding = padding
    self.content = content()
  }

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        Text(title)
          .font(theme.displayFont(size: 15))
          .foregroundStyle(theme.ink)
      }
      content
    }
    .padding(padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      shape.fill(
        LinearGradient(
          colors: [theme.panel, theme.panel.mix(with: theme.ink, by: 0.12)],
          startPoint: .top, endPoint: .bottom))
    )
    .overlay(shape.strokeBorder(theme.ink.opacity(0.7), lineWidth: 1.5))
  }
}
