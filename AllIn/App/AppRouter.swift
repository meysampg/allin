import Observation
import SwiftUI

@MainActor @Observable
final class AppRouter {
  private(set) var screen: Screen
  private(set) var tableSetup: TableSetup?
  private(set) var reviewRequest: ReviewRequest?
  private(set) var venueID: String?
  private(set) var lessonRequest: LessonRequest?
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

  func openCareer() {
    change { self.screen = .career }
  }

  func openVenue(_ id: String) {
    change {
      self.venueID = id
      self.screen = .venue
    }
  }

  func openLesson(_ request: LessonRequest) {
    change {
      self.lessonRequest = request
      self.venueID = request.venueID
      self.screen = .lesson
    }
  }

  /// Back to the venue the lesson was played from.
  func closeLesson() {
    change {
      if let id = self.lessonRequest?.venueID { self.venueID = id }
      self.lessonRequest = nil
      self.screen = .venue
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
