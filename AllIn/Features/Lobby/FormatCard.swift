import AllInUI
import SwiftUI

struct FormatCard: View {
  let format: TableSetup.Format
  let isSelected: Bool
  let action: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    Button(action: action) {
      VStack(alignment: .leading, spacing: 6) {
        icon
        Text(Self.title(format)).font(theme.bodyFont(size: 14, weight: .bold)).foregroundStyle(theme.ink)
        Text(Self.subtitle(format)).font(theme.bodyFont(size: 12)).foregroundStyle(theme.ink.opacity(0.7))
        if let note = Self.lockedNote(format) {
          // Ink on the desaturated panel is about 12:1; the card reads as locked from the grey fill and the lock.
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "lock.fill")
            Text(note)
          }
          .font(theme.bodyFont(size: 11, weight: .semibold))
          .foregroundStyle(theme.ink)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(shape.fill(theme.panel).saturation(format.isPlayable ? 1 : 0).opacity(format.isPlayable ? 1 : 0.9))
      .overlay(shape.strokeBorder(borderColor, style: borderStyle))
      .contentShape(shape)
    }
    .buttonStyle(FormatCardButtonStyle())
    .disabled(!format.isPlayable)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("lobby.format.\(format.rawValue)")
  }

  private var borderColor: Color {
    isSelected ? theme.gold : theme.ink.opacity(format.isPlayable ? 0.7 : 0.45)
  }

  private var borderStyle: StrokeStyle {
    StrokeStyle(lineWidth: isSelected ? 3 : 1.5, dash: format.isPlayable ? [] : [5, 3])
  }

  private var icon: some View {
    let (text, symbol) = Self.iconSpec(format)
    return ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.felt.opacity(0.85))
        .saturation(format.isPlayable ? 1 : 0)
      VStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: format == .tournament ? 34 : 26, weight: .bold))
        Text(text).font(theme.bodyFont(size: 12, weight: .semibold))
      }
      .foregroundStyle(theme.parchment)
    }
    .frame(height: 90)
  }

  private static func iconSpec(_ format: TableSetup.Format) -> (String, String) {
    switch format {
    case .cash6Max: ("6 seats", "person.3.fill")
    case .fullRing: ("9 seats", "person.3.sequence.fill")
    case .headsUp: ("1 vs 1", "person.2.fill")
    case .sitAndGo: ("trophy", "trophy.fill")
    case .tournament: ("big trophy", "trophy.fill")
    }
  }

  static func title(_ format: TableSetup.Format) -> String {
    switch format {
    case .cash6Max: "Cash 6-max"
    case .fullRing: "Full Ring"
    case .headsUp: "Heads-Up"
    case .sitAndGo: "Sit & Go"
    case .tournament: "Tournament"
    }
  }

  static func subtitle(_ format: TableSetup.Format) -> String {
    switch format {
    case .cash6Max: "most popular"
    case .fullRing: "tighter, slower"
    case .headsUp: "duel a rival"
    case .sitAndGo: "6 or 9 players"
    case .tournament: "27–180 players"
    }
  }

  static func lockedNote(_ format: TableSetup.Format) -> String? {
    switch format {
    case .cash6Max, .headsUp: nil
    case .fullRing: "Opens with the Guild Hall update"
    case .sitAndGo, .tournament: "Opens with the Royal Keep update"
    }
  }
}

/// Draws the label as is. The system styles fade a disabled button's content, which made the locked cards unreadable;
/// the card dims itself (grey fill, dashed border, lock) while keeping the text at full contrast.
private struct FormatCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
  }
}
