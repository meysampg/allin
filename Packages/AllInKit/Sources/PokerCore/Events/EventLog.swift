/// One event in a hand's log.
public struct LoggedEvent: Codable, Sendable, Hashable {
  /// Position in the full (host) log, from 0. Filtered views keep the original numbers, so gaps are expected.
  public let seq: Int
  public let handID: HandID
  public let visibility: Visibility
  public let event: GameEvent

  public init(seq: Int, handID: HandID, event: GameEvent) {
    self.seq = seq
    self.handID = handID
    self.visibility = event.visibility
    self.event = event
  }
}

/// The append-only log of one hand. The host's log is the hand history; seats and spectators get ``filtered(for:)``.
public struct EventLog: Codable, Sendable, Hashable {
  public let handID: HandID
  public private(set) var events: [LoggedEvent] = []

  public init(handID: HandID) { self.handID = handID }

  /// Appends one event and returns it with its sequence number.
  @discardableResult
  public mutating func append(_ event: GameEvent) -> LoggedEvent {
    let logged = LoggedEvent(seq: events.count, handID: handID, event: event)
    events.append(logged)
    return logged
  }

  /// Appends everything a reducer step produced and returns the new entries.
  @discardableResult
  public mutating func append(_ step: HandStep) -> [LoggedEvent] {
    EventMapper.events(for: step).map { append($0) }
  }

  /// Builds the complete host log of a finished (or running) hand from its start step and later steps.
  public init(handID: HandID, steps: [HandStep]) {
    self.init(handID: handID)
    for step in steps { append(step) }
  }

  /// The events `viewer` may see, in order.
  public func filtered(for viewer: Viewer) -> [LoggedEvent] {
    events.filter { viewer.canSee($0.visibility) }
  }

  /// The log as seen by `viewer`, still an ``EventLog``.
  public func view(for viewer: Viewer) -> EventLog {
    var copy = EventLog(handID: handID)
    copy.events = filtered(for: viewer)
    return copy
  }
}
