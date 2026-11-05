import AllInUI
import Curriculum
import SwiftUI

/// Screen 3: a venue chapter with its host banner, node list and skill meters.
struct VenueScreen: View {
  let venueID: String
  @Environment(AppModel.self) private var model
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  init(venueID: String) {
    self.venueID = venueID
  }

  var body: some View {
    let service = model.curriculum
    VStack(alignment: .leading, spacing: 0) {
      if let library = service.library, let venue = library.venue(venueID) {
        header(venue)
        VenueBanner(host: venue.host, reduceMotion: model.effectiveReduceMotion(system: systemReduceMotion))
          .padding(.top, 14)
        HStack(alignment: .top, spacing: 24) {
          nodeList(venue: venue, library: library, service: service)
          ChapterSkillsPanel(meters: service.meters(for: venue))
            .frame(width: 320)
        }
        .padding(.top, 22)
        Spacer(minLength: 0)
      } else {
        HStack {
          backButton
          Text("This venue is not available.")
            .font(theme.bodyFont(size: 15))
            .foregroundStyle(theme.parchment)
        }
        Spacer(minLength: 0)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(theme.night)
  }

  private var backButton: some View {
    Button("\u{2190} Map") { model.router.openCareer() }
      .buttonStyle(.fantasy(.small))
      .accessibilityIdentifier("venue.back")
  }

  private func header(_ venue: Venue) -> some View {
    HStack(spacing: 12) {
      backButton
      Text(model.curriculum.library?.realmVenue(venue.id)?.name ?? venue.name)
        .font(theme.bodyFont(size: 17, weight: .bold))
        .foregroundStyle(theme.parchment)
        .accessibilityIdentifier("venue.title")
      Text(venue.chapter)
        .font(theme.bodyFont(size: 13))
        .foregroundStyle(theme.mute)
        .accessibilityIdentifier("venue.chapter")
    }
  }

  private func nodeList(venue: Venue, library: ContentLibrary, service: CurriculumService) -> some View {
    VStack(spacing: 12) {
      ForEach(venue.nodes) { node in
        NodeRow(
          node: node, title: library.title(of: node), status: service.nodeStatus(node, in: venue),
          stars: service.nodeRecord(node.id)?.stars ?? 0
        ) { play(node, in: venue) }
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func play(_ node: VenueNode, in venue: Venue) {
    let router = model.router
    func lesson(_ content: LessonRequest.Content) {
      router.openLesson(
        LessonRequest(venueID: venue.id, nodeID: node.id, content: content, seed: model.newSessionSeed()))
    }
    switch node.kind {
    case .lesson: if let id = node.lesson { lesson(.lesson(id)) }
    case .drill: if let id = node.drill { lesson(.drill(id)) }
    case .table: if let spec = node.table { router.startTable(.career(spec, seed: model.newSessionSeed())) }
    case .boss: router.go(.boss)
    }
  }
}
