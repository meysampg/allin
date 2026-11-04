public enum SeedMix {
  /// SplitMix64-style finaliser over the inputs; stable across platforms and runs.
  public static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
    var z = a &+ 0x9E37_79B9_7F4A_7C15 &* (b &+ 1)
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  public static func mix(_ a: UInt64, _ b: UInt64, _ c: UInt64) -> UInt64 {
    mix(mix(a, b), c)
  }
}
