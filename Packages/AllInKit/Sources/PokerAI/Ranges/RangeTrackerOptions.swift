public struct RangeTrackerOptions: Sendable, Hashable {
  /// After each update, normalized weights below this become 0.
  public var pruneBelow: Float
  /// Preflop: one representative live combo per HandClass, its likelihood applied to the whole class
  /// (exact for class-based preflop strategies).
  public var preflopByClass: Bool
  /// Parallel chunks over combos in the async update.
  public var chunks: Int

  public init(pruneBelow: Float = 1e-4, preflopByClass: Bool = true, chunks: Int = 8) {
    self.pruneBelow = pruneBelow
    self.preflopByClass = preflopByClass
    self.chunks = chunks
  }

  public static let standard = RangeTrackerOptions()
}
