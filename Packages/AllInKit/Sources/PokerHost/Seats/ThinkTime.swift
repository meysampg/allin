public enum GameSpeed: String, Codable, Sendable, CaseIterable {
  case relaxed, normal, turbo

  public var factor: Double {
    switch self {
    case .relaxed: 1.4
    case .normal: 1.0
    case .turbo: 0.3
    }
  }
}

/// How long a bot "thinks" before answering, for UI pacing.
public struct ThinkTime: Sendable, Hashable {
  /// No sleep (tests, sims).
  public static let instant = ThinkTime(base: .zero, jitter: .zero, speed: .normal, isInstant: true)

  public let base: Duration
  public let jitter: Duration
  public let speed: GameSpeed
  public let isInstant: Bool

  public init(base: Duration, jitter: Duration, speed: GameSpeed = .normal) {
    self.init(base: base, jitter: jitter, speed: speed, isInstant: false)
  }

  private init(base: Duration, jitter: Duration, speed: GameSpeed, isInstant: Bool) {
    self.base = base
    self.jitter = jitter
    self.speed = speed
    self.isInstant = isInstant
  }

  /// The delay for one decision: `max(120 ms, (base + U(0, jitter)) x speed.factor)`, zero when `.instant`.
  public func delay(using rng: inout some RandomNumberGenerator) -> Duration {
    if isInstant { return .zero }
    let unit = Double.random(in: 0..<1, using: &rng)
    let ms = (Self.milliseconds(base) + unit * Self.milliseconds(jitter)) * speed.factor
    return .milliseconds(max(120.0, ms))
  }

  private static func milliseconds(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
  }
}
