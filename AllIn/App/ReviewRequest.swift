import AllInStore

/// What the review screen shows.
enum ReviewRequest: Hashable, Sendable {
  case archived(ArchiveKey)
  case demo(seed: UInt64)
}

enum ReviewPresentation {
  /// A route of its own: back goes to the menu.
  case standalone
  /// Inside the table screen: back closes the overlay and the session keeps running underneath.
  case overlay(onBack: @MainActor () -> Void)
}
