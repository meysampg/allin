import Foundation

enum Screen: String, CaseIterable, Hashable, Sendable {
  case menu, career, venue, lesson, lobby, table, review, boss, result, tournament, gym, rivals, mygame, settings, arena

  var title: String {
    switch self {
    case .menu: "Main Menu"
    case .career: "Career"
    case .venue: "Venue"
    case .lesson: "Lesson"
    case .lobby: "Quick Play"
    case .table: "Table"
    case .review: "Hand Review"
    case .boss: "Boss Match"
    case .result: "Result"
    case .tournament: "Tournament"
    case .gym: "Gym"
    case .rivals: "Rivals"
    case .mygame: "My Game"
    case .settings: "Settings"
    case .arena: "Arena"
    }
  }

  var isImplemented: Bool {
    switch self {
    case .menu, .lobby, .table, .review: true
    default: false
    }
  }
}
