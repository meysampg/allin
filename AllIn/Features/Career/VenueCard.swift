import AllInUI
import Curriculum
import SwiftUI

/// One venue on the career map: silhouette, name and status. Open and cleared venues can be tapped.
struct VenueCard: View {
  let venue: RealmVenue
  let status: VenueStatus
  let onOpen: () -> Void
  @Environment(\.theme) private var theme

  static let size = CGSize(width: 190, height: 168)

  private var isOpen: Bool {
    if case .open = status { return true }
    return false
  }

  private var isTappable: Bool {
    switch status {
    case .open, .cleared: true
    case .locked, .comingSoon: false
    }
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    VStack(spacing: 6) {
      VenueSilhouette(icon: venue.icon)
        .frame(height: 92)
        .overlay(alignment: .topTrailing) {
          if isOpen { PlayerToken().offset(x: 10, y: -12) }
        }
      Text(venue.name)
        .font(theme.displayFont(size: 15))
        .foregroundStyle(theme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityIdentifier("career.venue.\(venue.id).name")
      Tag(statusText, style: statusStyle)
        .accessibilityIdentifier("career.venue.\(venue.id).status")
    }
    .padding(10)
    .frame(width: Self.size.width, height: Self.size.height)
    .background(shape.fill(theme.panel))
    .overlay(shape.strokeBorder(isOpen ? theme.gold : theme.ink.opacity(0.7), lineWidth: isOpen ? 4 : 1.5))
    .opacity(isTappable ? 1 : 0.5)
    .contentShape(shape)
    .onTapGesture { if isTappable { onOpen() } }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(isTappable ? .isButton : [])
    .accessibilityIdentifier("career.venue.\(venue.id)")
  }

  private var statusText: String {
    switch status {
    case .cleared(let stars):
      "\u{2713} cleared \u{00B7} " + String(repeating: "\u{2605}", count: max(stars, 0))
        + String(repeating: "\u{2606}", count: max(3 - stars, 0))
    case .open(let done, let total): "\u{25CF} \(done) / \(total) nodes"
    case .locked(let reason): "\u{1F512} \(reason)"
    case .comingSoon: venue.lockedText.map { "\u{1F512} \($0)" } ?? "\u{1F512}"
    }
  }

  private var statusStyle: TagStyle {
    switch status {
    case .cleared: .good
    case .open: .gold
    case .locked, .comingSoon: .plain
    }
  }
}

/// The hero's token on the open venue.
struct PlayerToken: View {
  @Environment(\.theme) private var theme

  var body: some View {
    ZStack {
      Circle().fill(theme.gold)
      Image(systemName: "figure.walk")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(theme.ink)
    }
    .frame(width: 34, height: 34)
    .overlay(Circle().strokeBorder(theme.ink, lineWidth: 2))
    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
    .accessibilityLabel("You are here")
    .accessibilityIdentifier("career.token")
  }
}
