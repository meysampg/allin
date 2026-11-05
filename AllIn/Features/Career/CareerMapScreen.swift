import AllInUI
import Curriculum
import SwiftUI

/// Screen 2: the realm map with four venues along a dashed road.
struct CareerMapScreen: View {
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme

  init() {}

  var body: some View {
    let service = model.curriculum
    let realm = service.library?.realm.venues ?? []
    ZStack(alignment: .topLeading) {
      GeometryReader { proxy in
        ZStack(alignment: .topLeading) {
          RealmPath()
            .stroke(theme.parchment.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 8]))
            .accessibilityElement()
            .accessibilityIdentifier("career.path")
          ForEach(Array(realm.enumerated()), id: \.element.id) { index, venue in
            let center = RealmLayout.point(index, in: proxy.size)
            VenueCard(venue: venue, status: service.venueStatus(venue)) { model.router.openVenue(venue.id) }
              .position(x: center.x, y: center.y)
          }
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        topBar(service: service, realm: realm)
        Spacer(minLength: 0)
        teachesPanel(realm: realm)
      }
      .padding(16)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(theme.night)
  }

  private func topBar(service: CurriculumService, realm: [RealmVenue]) -> some View {
    HStack(spacing: 12) {
      Button("\u{2190} Menu") { model.router.backToMenu() }
        .buttonStyle(.fantasy(.small))
        .accessibilityIdentifier("career.back")
      Text("Career")
        .font(theme.bodyFont(size: 17, weight: .bold))
        .foregroundStyle(theme.parchment)
        .accessibilityIdentifier("career.title")
      Spacer(minLength: 0)
      Tag("Gold \(model.profile.gold)", style: .gold)
        .accessibilityIdentifier("career.gold")
      Tag("Venue \(venueNumber(service: service, realm: realm)) of \(realm.count)")
        .accessibilityIdentifier("career.venueCount")
    }
  }

  private func venueNumber(service: CurriculumService, realm: [RealmVenue]) -> Int {
    guard let current = service.currentVenue(), let index = realm.firstIndex(of: current) else {
      return service.library == nil ? 0 : realm.count
    }
    return index + 1
  }

  private func teachesPanel(realm: [RealmVenue]) -> some View {
    ParchmentPanel(title: "What each venue teaches", padding: 12) {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(realm) { venue in
          Text("\(Self.emoji(venue.icon)) \(venue.teaches)")
            .font(theme.bodyFont(size: 12))
            .foregroundStyle(theme.ink)
            .lineLimit(1)
            .accessibilityIdentifier("career.teaches.\(venue.id)")
        }
      }
      .accessibilityElement(children: .contain)
    }
    .frame(width: 560)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("career.teaches")
  }

  private static func emoji(_ icon: VenueIcon) -> String {
    switch icon {
    case .village: "\u{1F3E0}"
    case .townHall: "\u{1F3DB}\u{FE0F}"
    case .castle: "\u{1F3F0}"
    case .cave: "\u{1F409}"
    }
  }
}
