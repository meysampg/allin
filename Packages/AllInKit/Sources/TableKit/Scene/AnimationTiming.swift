import Foundation

public enum AnimationBeat: Sendable, CaseIterable {
  case dealCard, flip, chipSlide, collect, boardSlide, showdownLift, award, handEndPause, fold, crossfade
}

/// Beat lengths in seconds. `speedFactor` multiplies them (GameSpeed.factor: relaxed 1.4, normal 1, turbo 0.3).
/// Under reduce motion every move becomes a crossfade and flips are instant.
public struct AnimationTiming: Sendable, Hashable {
  public var speedFactor: Double
  public var reduceMotion: Bool

  public init(speedFactor: Double = 1, reduceMotion: Bool = false) {
    self.speedFactor = speedFactor
    self.reduceMotion = reduceMotion
  }

  public func duration(_ beat: AnimationBeat) -> TimeInterval {
    let factor = max(speedFactor, 0)
    switch beat {
    case .flip: return reduceMotion ? 0 : 0.18 * factor
    case .handEndPause: return 0.80 * factor
    case .crossfade: return 0.15 * factor
    case .dealCard, .chipSlide, .collect, .boardSlide, .showdownLift, .award, .fold:
      return reduceMotion ? 0.15 * factor : Self.base(beat) * factor
    }
  }

  /// How long a dealt card takes to reach its seat (the `dealCard` beat is the gap between two cards).
  public var dealTravel: TimeInterval {
    reduceMotion ? 0.15 * max(speedFactor, 0) : 0.25 * max(speedFactor, 0)
  }

  private static func base(_ beat: AnimationBeat) -> TimeInterval {
    switch beat {
    case .dealCard: 0.09
    case .chipSlide: 0.25
    case .collect: 0.35
    case .boardSlide: 0.30
    case .showdownLift: 0.40
    case .award: 0.60
    case .fold: 0.20
    case .flip: 0.18
    case .handEndPause: 0.80
    case .crossfade: 0.15
    }
  }
}
