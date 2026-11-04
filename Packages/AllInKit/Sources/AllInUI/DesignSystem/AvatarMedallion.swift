import SwiftUI
import ThemeKit

public enum MedallionMood: Sendable { case idle, think, happy, tilt }

public struct AvatarMedallion: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var breathing = false

  private let characterID: String?
  private let name: String?
  private let size: CGFloat
  private let mood: MedallionMood
  private let isDimmed: Bool

  public init(
    characterID: String?, name: String? = nil, size: CGFloat = 54, mood: MedallionMood = .idle,
    isDimmed: Bool = false
  ) {
    self.characterID = characterID
    self.name = name
    self.size = size
    self.mood = mood
    self.isDimmed = isDimmed
  }

  public var body: some View {
    VStack(spacing: 3) {
      medallion
        .scaleEffect(mood == .think && !reduceMotion && breathing ? 1.06 : 1)
        .animation(
          mood == .think && !reduceMotion
            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: breathing
        )
        .onAppear { breathing = true }
      if let name {
        Text(name)
          .font(theme.bodyFont(size: max(size * 0.22, 10), weight: .semibold))
          .foregroundStyle(theme.ink)
          .lineLimit(1)
      }
    }
    .opacity(isDimmed ? 0.5 : 1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(name ?? characterID ?? "Player")
  }

  private var medallion: some View {
    let spec = Self.spec(theme: theme, characterID: characterID)
    return ZStack {
      Circle().fill(theme.parchment)
      if let symbol = spec.symbol {
        Image(systemName: symbol)
          .font(.system(size: size * 0.46, weight: .bold))
          .foregroundStyle(spec.ring)
      } else {
        Text(spec.initial)
          .font(theme.displayFont(size: size * 0.46))
          .foregroundStyle(spec.ring)
      }
    }
    .overlay(Circle().strokeBorder(spec.ring, lineWidth: max(size * 0.07, 2)))
    .overlay(alignment: .bottomTrailing) {
      if let badge = moodBadge {
        Image(systemName: badge)
          .font(.system(size: size * 0.22, weight: .bold))
          .foregroundStyle(theme.ink)
          .padding(2)
          .background(Circle().fill(theme.parchment))
          .offset(x: 2, y: 2)
      }
    }
    .frame(width: size, height: size)
  }

  private var moodBadge: String? {
    switch mood {
    case .idle: return nil
    case .think: return "ellipsis"
    case .happy: return "face.smiling"
    case .tilt: return "cloud.bolt.fill"
    }
  }

  private struct Spec {
    var symbol: String?
    var ring: Color
    var initial: String
  }

  private static func spec(theme: Theme, characterID: String?) -> Spec {
    let id = characterID ?? "random"
    let fallbackInitial = id.first.map { String($0).uppercased() } ?? "?"
    if case .procedural(_, let params) = theme.resolver.resolve(.avatar(id)) {
      let symbol = params.string("symbol", default: "")
      return Spec(
        symbol: symbol.isEmpty ? nil : symbol,
        ring: Color(params.color("ring", default: theme.resolver.palette[.mute])),
        initial: params.string("initial", default: fallbackInitial))
    }
    return Spec(symbol: nil, ring: theme.mute, initial: fallbackInitial)
  }
}
