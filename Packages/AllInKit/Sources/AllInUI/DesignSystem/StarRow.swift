import SwiftUI

public struct StarRow: View {
  @Environment(\.theme) private var theme
  private let filled: Int
  private let total: Int
  private let size: CGFloat

  public init(filled: Int, total: Int = 3, size: CGFloat = 16) {
    self.filled = filled
    self.total = total
    self.size = size
  }

  public var body: some View {
    let count = max(total, 0)
    let lit = min(max(filled, 0), count)
    HStack(spacing: 2) {
      ForEach(0..<count, id: \.self) { index in
        Text(index < lit ? "\u{2605}" : "\u{2606}")
          .font(.system(size: size))
          .foregroundStyle(index < lit ? theme.gold : theme.mute)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(lit) of \(count) stars")
  }
}
