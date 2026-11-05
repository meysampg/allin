import AllInUI
import Curriculum
import SwiftUI

/// The venue banner: the host medallion waving and the host's line.
struct VenueBanner: View {
  let host: VenueHost
  let reduceMotion: Bool
  @Environment(\.theme) private var theme
  @State private var waving = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    HStack(spacing: 18) {
      AvatarMedallion(characterID: host.artKey, size: 72)
        .rotationEffect(.degrees(reduceMotion ? 0 : (waving ? 7 : -7)), anchor: .bottom)
        .animation(
          reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: waving
        )
        .accessibilityIdentifier("venue.hostAvatar")
      Text("\(host.name): \(host.line)")
        .font(theme.displayFont(size: 20))
        .foregroundStyle(theme.ink)
        .accessibilityIdentifier("venue.host")
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 22)
    .frame(maxWidth: .infinity)
    .frame(height: 110)
    .background(
      shape.fill(
        LinearGradient(colors: [theme.parchment, theme.gold.opacity(0.45)], startPoint: .leading, endPoint: .trailing))
    )
    .overlay(shape.strokeBorder(theme.ink.opacity(0.7), lineWidth: 1.5))
    .onAppear { if !reduceMotion { waving = true } }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("venue.banner")
  }
}
