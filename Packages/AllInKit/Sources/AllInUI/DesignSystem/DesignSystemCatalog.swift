#if DEBUG
  import PokerCore
  import SwiftUI

  /// Debug-only gallery of every design-system component in every style.
  public struct DesignSystemCatalog: View {
    @Environment(\.theme) private var theme
    @State private var pick = "questions"

    public init() {}

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          section("Buttons") {
            HStack {
              Button("Primary") {}.buttonStyle(.fantasy(.primary))
              Button("Secondary") {}.buttonStyle(.fantasy(.secondary))
              Button("Small") {}.buttonStyle(.fantasy(.small))
              Button("Disabled") {}.buttonStyle(.fantasy(.secondary)).disabled(true)
            }
          }
          section("Panel") {
            ParchmentPanel(title: "Parchment panel") {
              Text("Body text on parchment.").font(theme.bodyFont(size: 13)).foregroundStyle(theme.ink)
            }
          }
          section("Tags") {
            HStack {
              Tag("Plain", style: .plain)
              Tag("Gold", systemImage: "star.fill", style: .gold)
              Tag("Good", style: .good)
              Tag("Bad", style: .bad)
              Tag("Muted", style: .muted)
              Tag("Dark", style: .dark)
            }
            TagPicker(
              options: [
                TagOption("questions", label: "Questions", id: "questions"),
                TagOption("review", label: "Review", id: "review"),
                TagOption("off", label: "Off", id: "off"),
              ], selection: $pick, idPrefix: "catalog.coach")
          }
          section("Meter and stars") {
            Meter(value: 0.7, label: "Strength")
            Meter(value: 0.25, label: "Tinted", tint: theme.bad)
            StarRow(filled: 2)
          }
          section("Avatars") {
            HStack(alignment: .top, spacing: 12) {
              ForEach(["you", "grumli", "zib", "vexa", "mott", "oryn", "random"], id: \.self) { id in
                AvatarMedallion(characterID: id, name: id.capitalized)
              }
              AvatarMedallion(characterID: "grumli", name: "Think", mood: .think)
              AvatarMedallion(characterID: "zib", name: "Dimmed", isDimmed: true)
            }
          }
          section("Cards") {
            HStack {
              CardView(card: try? Card("Qs"))
              CardView(card: try? Card("Ah"))
              CardView(card: try? Card("Td"), fourColor: true)
              CardView(card: try? Card("2c"), fourColor: true)
              CardView(card: try? Card("Ks"), size: .small)
              CardView(card: nil)
              CardView(card: nil, faceDown: true)
              CardView(card: try? Card("9h"), size: .width(66))
            }
          }
        }
        .padding(16)
      }
      .background(theme.night)
      .allInTheme(theme)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(theme.displayFont(size: 14)).foregroundStyle(theme.parchment)
        content()
      }
    }
  }

  #Preview {
    DesignSystemCatalog().frame(width: 720, height: 800)
  }
#endif
