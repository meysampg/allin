/// Who may see an event.
public enum Visibility: Codable, Sendable, Hashable {
  /// Everyone at the table and every spectator.
  case `public`
  /// Only the given seat (and the host).
  case seat(Int)
  /// Only the host: burns, the deck, the seed and mucked hands.
  case hostOnly
}

/// Who is looking at a log.
public enum Viewer: Codable, Sendable, Hashable {
  /// A player: sees public events and the events private to their seat.
  case seat(Int)
  /// A watcher: sees public events only.
  case spectator
  /// The authoritative host: sees everything.
  case host

  /// Whether this viewer may see an event with the given visibility.
  public func canSee(_ visibility: Visibility) -> Bool {
    switch (self, visibility) {
    case (.host, _): true
    case (_, .public): true
    case (.seat(let viewer), .seat(let owner)): viewer == owner
    default: false
    }
  }
}
