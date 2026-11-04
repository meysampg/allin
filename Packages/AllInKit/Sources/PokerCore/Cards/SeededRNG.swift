/// Deterministic, seedable xoshiro256** generator (Blackman and Vigna). The 64-bit seed is expanded to the
/// 256-bit state with SplitMix64, as the authors recommend. Same seed, same sequence, on every platform.
public struct SeededRNG: RandomNumberGenerator, Sendable, Equatable {
  private var s0: UInt64
  private var s1: UInt64
  private var s2: UInt64
  private var s3: UInt64

  public init(seed: UInt64) {
    var sm = SplitMix64(state: seed)
    s0 = sm.next()
    s1 = sm.next()
    s2 = sm.next()
    s3 = sm.next()
  }

  public mutating func next() -> UInt64 {
    let result = rotl(s1 &* 5, 7) &* 9
    let t = s1 << 17
    s2 ^= s0
    s3 ^= s1
    s1 ^= s2
    s0 ^= s3
    s2 ^= t
    s3 = rotl(s3, 45)
    return result
  }

  @inline(__always) private func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }
}

/// SplitMix64, used only for seed expansion.
struct SplitMix64: Sendable {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
