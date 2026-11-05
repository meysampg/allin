import AllInUI
import Curriculum
import SwiftUI

/// One node of a venue chapter: status, kind and title, stars, and Play on the current node.
struct NodeRow: View {
  let node: VenueNode
  let title: String
  let status: NodeStatus
  let stars: Int
  let onPlay: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    let id = node.id
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    let isCurrent = status == .available
    HStack(spacing: 12) {
      Tag(statusSymbol, style: statusStyle)
        .frame(width: 44)
        .accessibilityIdentifier("venue.node.\(id).status")
      HStack {
        Text("\(Self.icon(node.kind)) \(Self.label(node.kind)) \u{00B7} \(title)")
          .font(theme.bodyFont(size: 14, weight: isCurrent ? .semibold : .regular))
          .foregroundStyle(theme.ink)
          .lineLimit(1)
          .accessibilityIdentifier("venue.node.\(id).title")
        Spacer(minLength: 0)
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .background(shape.fill(theme.panel))
      .overlay(shape.strokeBorder(isCurrent ? theme.gold : theme.ink.opacity(0.7), lineWidth: isCurrent ? 3.5 : 1.5))
      if status == .completed {
        StarRow(filled: stars, size: 18)
          .accessibilityIdentifier("venue.node.\(id).stars")
      }
      if isCurrent {
        Button("Play", action: onPlay)
          .buttonStyle(.fantasy(.primary))
          .accessibilityIdentifier("venue.node.\(id).play")
      }
    }
    .opacity(status == .locked ? 0.55 : 1)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("venue.node.\(id)")
  }

  private var statusSymbol: String {
    switch status {
    case .completed: "\u{2713}"
    case .available: "\u{25CF}"
    case .locked: "\u{1F512}"
    }
  }

  private var statusStyle: TagStyle {
    switch status {
    case .completed: .good
    case .available: .gold
    case .locked: .plain
    }
  }

  static func icon(_ kind: NodeKind) -> String {
    switch kind {
    case .lesson: "\u{1F4DC}"
    case .drill: "\u{1F3AF}"
    case .table: "\u{1F37A}"
    case .boss: "\u{2694}\u{FE0F}"
    }
  }

  static func label(_ kind: NodeKind) -> String {
    switch kind {
    case .lesson: "Lesson"
    case .drill: "Drill"
    case .table: "Table session"
    case .boss: "Boss"
    }
  }
}
