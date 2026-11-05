import Observation
import SwiftUI

@MainActor @Observable
final class AppRouter {
  private(set) var screen: Screen
  private(set) var tableSetup: TableSetup?
  private(set) var reviewRequest: ReviewRequest?
  /// Set by the app model; transitions are not animated when true.
  var reduceMotion = false

  init(initial: Screen = .menu) {
    screen = initial
  }

  func go(_ screen: Screen) {
    change { self.screen = screen }
  }

  func startTable(_ setup: TableSetup) {
    change {
      self.tableSetup = setup
      self.screen = .table
    }
  }

  func openReview(_ request: ReviewRequest) {
    change {
      self.reviewRequest = request
      self.screen = .review
    }
  }

  func leaveTable() {
    change {
      self.tableSetup = nil
      self.screen = .lobby
    }
  }

  func backToMenu() {
    change { self.screen = .menu }
  }

  private func change(_ body: () -> Void) {
    if reduceMotion {
      body()
    } else {
      withAnimation(.easeInOut(duration: 0.25), body)
    }
  }
}
