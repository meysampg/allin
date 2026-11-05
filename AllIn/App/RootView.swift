import AllInUI
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  var body: some View {
    let router = model.router
    ZStack {
      content(router: router)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(router.screen.rawValue)")
        .id(router.screen)
        .transition(model.effectiveReduceMotion(system: systemReduceMotion) ? .identity : .opacity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(model.theme.night)
    .allInTheme(model.theme)
    .onAppear { router.reduceMotion = model.effectiveReduceMotion(system: systemReduceMotion) }
    .onChange(of: systemReduceMotion) { router.reduceMotion = model.effectiveReduceMotion(system: $1) }
  }

  @ViewBuilder
  private func content(router: AppRouter) -> some View {
    switch router.screen {
    case .menu: MainMenuView()
    case .career: CareerMapScreen()
    case .venue:
      VenueScreen(venueID: router.venueID ?? model.curriculum.currentVenue()?.id ?? "")
    case .lesson:
      let request = router.lessonRequest ?? model.fallbackLessonRequest()
      LessonScreen(request: request).id(request)
    case .lobby: LobbyView()
    case .table:
      let setup = router.tableSetup ?? .demo(seed: model.newSessionSeed())
      TableScreen(setup: setup).id(setup)
    case .review:
      let request = router.reviewRequest ?? .demo(seed: 7)
      ReviewScreen(request: request, presentation: .standalone).id(request)
    default: PlaceholderScreen(screen: router.screen)
    }
  }
}
