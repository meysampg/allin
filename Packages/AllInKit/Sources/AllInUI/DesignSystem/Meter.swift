import SwiftUI

/// Rune bar, value clamped to 0...1.
public struct Meter: View {
  @Environment(\.theme) private var theme
  private let value: Double
  private let label: String?
  private let tint: Color?

  public init(value: Double, label: String? = nil, tint: Color? = nil) {
    self.value = value
    self.label = label
    self.tint = tint
  }

  public var body: some View {
    let clamped = min(max(value.isFinite ? value : 0, 0), 1)
    VStack(alignment: .leading, spacing: 3) {
      if let label {
        Text(label)
          .font(theme.bodyFont(size: 11, weight: .semibold))
          .foregroundStyle(theme.ink)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(theme.ink.opacity(0.18))
          Capsule()
            .fill(
              tint.map { AnyShapeStyle($0) }
                ?? AnyShapeStyle(
                  LinearGradient(colors: [theme.rune, theme.gold], startPoint: .leading, endPoint: .trailing))
            )
            .frame(width: proxy.size.width * clamped)
        }
        .overlay(Capsule().strokeBorder(theme.ink.opacity(0.6), lineWidth: 1))
      }
      .frame(height: 10)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label ?? "Meter")
    .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
  }
}
