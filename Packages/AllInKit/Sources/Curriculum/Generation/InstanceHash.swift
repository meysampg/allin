import Foundation

/// FNV-1a 64 (never `Hasher`, which is seeded per process).
enum InstanceHash {
  static func fnv1a64(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
  }

  /// 16 lowercase hex digits.
  static func hex(_ text: String) -> String {
    let digits = String(fnv1a64(text), radix: 16)
    return String(repeating: "0", count: 16 - digits.count) + digits
  }
}
