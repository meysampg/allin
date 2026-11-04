import Foundation

public enum TableSceneMode: Sendable, Hashable {
  /// A hand being played; events arrive one by one.
  case live
  /// A static position set with `show(_:)`; no queue, no animation.
  case spot
  /// Like live, with a recorded log enqueued by the caller.
  case replay
  /// A small decorative table: no seat labels, no sound, faster beats.
  case miniature
}

public struct TableSceneOptions: Sendable {
  public var timing = AnimationTiming()
  public var hud: TableHUD = .basic
  public var fourColorDeck = false
  public var driver: AnimationQueue.Driver = .spriteKit
  public var mode: TableSceneMode = .live

  public init(
    timing: AnimationTiming = AnimationTiming(), hud: TableHUD = .basic, fourColorDeck: Bool = false,
    driver: AnimationQueue.Driver = .spriteKit, mode: TableSceneMode = .live
  ) {
    self.timing = timing
    self.hud = hud
    self.fourColorDeck = fourColorDeck
    self.driver = driver
    self.mode = mode
  }
}
