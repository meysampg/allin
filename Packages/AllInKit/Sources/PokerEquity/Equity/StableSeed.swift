import PokerCore

public enum StableSeed {
  /// SplitMix64-style mix of two 64-bit values. Stable across processes and platforms.
  public static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
    var z = a &+ 0x9E37_79B9_7F4A_7C15 &+ (b &+ 1) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// FNV-1a 64 over: seat, street, holeCards, board, pot, history count and every entry's (seat, chipsAdded).
  /// Integers are fed as 8 little-endian bytes, cards as their one-byte index.
  public static func of(_ context: DecisionContext) -> UInt64 {
    var h = FNV()
    h.add(context.seat)
    h.add(Street.allCases.firstIndex(of: context.street) ?? 0)
    for c in context.holeCards { h.add(byte: c.index) }
    for c in context.board { h.add(byte: c.index) }
    h.add(context.pot)
    h.add(context.history.count)
    for e in context.history {
      h.add(e.seat)
      h.add(e.chipsAdded)
    }
    return h.value
  }
}

private struct FNV {
  var value: UInt64 = 0xcbf2_9ce4_8422_2325

  mutating func add(byte: UInt8) {
    value ^= UInt64(byte)
    value = value &* 0x100_0000_01b3
  }

  mutating func add(_ int: Int) {
    var v = UInt64(bitPattern: Int64(int))
    for _ in 0..<8 {
      add(byte: UInt8(truncatingIfNeeded: v))
      v >>= 8
    }
  }
}
