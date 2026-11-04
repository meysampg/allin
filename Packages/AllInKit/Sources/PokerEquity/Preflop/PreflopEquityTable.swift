import Foundation
import PokerCore

/// Exact heads-up preflop hand-vs-hand equity for every suit pattern, loaded from `Resources/preflop169.bin`.
///
/// Two-hand matchups are canonicalised over the 24 suit permutations and the hand order, which leaves about 47k
/// unique keys. Deviation from PLAN's "about 120 KB" 169x169 table: exact suit patterns plus tie data take about
/// 380 KB, but give exact answers for suited and offsuit interactions between the two hands.
///
/// File format (little-endian): magic `"AIPF"`, `UInt16 version = 1`, `UInt16 reserved`, `UInt32 count`,
/// `UInt32 boardsPerMatchup`, then `count` ascending `UInt32` keys, then `count` pairs of `UInt16` (`eqQ`, `tieQ`),
/// each the first hand's equity and tie fraction scaled by 65535.
public struct PreflopEquityTable: Sendable {
  /// Boards enumerated for every matchup: C(48, 5).
  static let boardsPerMatchup: UInt32 = 1_712_304
  static let headerSize = 16
  static let version: UInt16 = 1
  private static let magic: [UInt8] = [0x41, 0x49, 0x50, 0x46]  // "AIPF"

  /// Loaded from `Bundle.module` ("Resources/preflop169.bin"); nil if the file is missing or corrupt.
  public static let shared: PreflopEquityTable? = {
    guard
      let url = Bundle.module.url(forResource: "preflop169", withExtension: "bin", subdirectory: "Resources"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? PreflopEquityTable(data: data)
  }()

  public enum LoadError: Error, Sendable, Equatable {
    case badMagic
    case unsupportedVersion(UInt16)
    case truncated
    case invalid
  }

  public let entryCount: Int
  private let keys: [UInt32]
  private let equityQ: [UInt16]
  private let tieQ: [UInt16]

  public init(data: Data) throws {
    let bytes = [UInt8](data)
    guard bytes.count >= Self.headerSize else { throw LoadError.truncated }
    guard Array(bytes[0..<4]) == Self.magic else { throw LoadError.badMagic }
    let version = Self.readU16(bytes, 4)
    guard version == Self.version else { throw LoadError.unsupportedVersion(version) }
    let count = Int(Self.readU32(bytes, 8))
    guard Self.readU32(bytes, 12) == Self.boardsPerMatchup else { throw LoadError.invalid }
    guard count > 0, count <= 1_000_000 else { throw LoadError.invalid }
    guard bytes.count == Self.headerSize + count * 8 else { throw LoadError.truncated }
    var keys = [UInt32](repeating: 0, count: count)
    var eq = [UInt16](repeating: 0, count: count)
    var tie = [UInt16](repeating: 0, count: count)
    let keyBase = Self.headerSize
    let valueBase = keyBase + count * 4
    for i in 0..<count {
      keys[i] = Self.readU32(bytes, keyBase + i * 4)
      eq[i] = Self.readU16(bytes, valueBase + i * 4)
      tie[i] = Self.readU16(bytes, valueBase + i * 4 + 2)
      if i > 0, keys[i] <= keys[i - 1] { throw LoadError.invalid }
    }
    entryCount = count
    self.keys = keys
    equityQ = eq
    tieQ = tie
  }

  /// Hand vs hand, exact for the suit pattern (quantised to 1/65535). nil if the cards overlap.
  public func equity(_ hero: [Card], _ villain: [Card]) -> EquityResult? {
    guard hero.count == 2, villain.count == 2 else { return nil }
    guard CardSet(hero + villain).count == 4 else { return nil }
    let (key, flipped) = Self.canonicalKey(hero, villain)
    var lo = 0
    var hi = keys.count
    while lo < hi {
      let mid = (lo + hi) >> 1
      if keys[mid] < key { lo = mid + 1 } else { hi = mid }
    }
    guard lo < keys.count, keys[lo] == key else { return nil }
    let first = Double(equityQ[lo]) / 65535
    let tie = Double(tieQ[lo]) / 65535
    let equity = flipped ? 1 - first : first
    return EquityResult(
      win: max(equity - tie / 2, 0), tie: tie, equity: equity, samples: Int(Self.boardsPerMatchup), isExact: true)
  }

  /// All 24 permutations of the four suits, flattened (`perm * 4 + suit`).
  private static let suitPermutations: [UInt8] = {
    var out: [UInt8] = []
    for a in 0..<4 {
      for b in 0..<4 where b != a {
        for c in 0..<4 where c != a && c != b {
          let d = 6 - a - b - c
          out.append(contentsOf: [UInt8(a), UInt8(b), UInt8(c), UInt8(d)])
        }
      }
    }
    return out
  }()

  /// The 24-permutation + swap canonical key; `flipped` says whether hero became the second hand.
  /// Each hand's cards are sorted descending and packed as `(h1hi, h1lo, h2hi, h2lo)`; the minimum wins.
  public static func canonicalKey(_ hero: [Card], _ villain: [Card]) -> (key: UInt32, flipped: Bool) {
    precondition(hero.count == 2 && villain.count == 2, "Each hand needs 2 cards")
    let a = hero[0].index
    let b = hero[1].index
    let c = villain[0].index
    let d = villain[1].index
    var best0 = UInt32.max
    var best1 = UInt32.max
    suitPermutations.withUnsafeBufferPointer { perms in
      for p in 0..<24 {
        let base = p * 4
        @inline(__always) func map(_ idx: UInt8) -> UInt32 {
          UInt32((idx & ~3) | perms[base + Int(idx & 3)])
        }
        let ma = map(a)
        let mb = map(b)
        let mc = map(c)
        let md = map(d)
        let h = ma > mb ? (ma << 8 | mb) : (mb << 8 | ma)
        let v = mc > md ? (mc << 8 | md) : (md << 8 | mc)
        let k0 = h << 16 | v
        let k1 = v << 16 | h
        if k0 < best0 { best0 = k0 }
        if k1 < best1 { best1 = k1 }
      }
    }
    return best1 < best0 ? (best1, true) : (best0, false)
  }

  /// The four card indices of a key as (h1hi, h1lo, h2hi, h2lo).
  static func cards(ofKey key: UInt32) -> [Card] {
    [24, 16, 8, 0].map { Card(index: UInt8((key >> $0) & 0xFF)) }
  }

  static func makeFile(keys: [UInt32], equityQ: [UInt16], tieQ: [UInt16]) -> Data {
    var out = [UInt8]()
    out.reserveCapacity(headerSize + keys.count * 8)
    out.append(contentsOf: magic)
    appendU16(&out, version)
    appendU16(&out, 0)
    appendU32(&out, UInt32(keys.count))
    appendU32(&out, boardsPerMatchup)
    for k in keys { appendU32(&out, k) }
    for i in keys.indices {
      appendU16(&out, equityQ[i])
      appendU16(&out, tieQ[i])
    }
    return Data(out)
  }

  private static func readU16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }

  private static func readU32(_ b: [UInt8], _ o: Int) -> UInt32 {
    UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
  }

  private static func appendU16(_ out: inout [UInt8], _ v: UInt16) {
    out.append(UInt8(v & 0xFF))
    out.append(UInt8(v >> 8))
  }

  private static func appendU32(_ out: inout [UInt8], _ v: UInt32) {
    for s in [0, 8, 16, 24] { out.append(UInt8((v >> UInt32(s)) & 0xFF)) }
  }
}

extension EquityCalculator {
  /// Table if loaded, else exact enumeration.
  public static func preflop(_ hero: [Card], _ villain: [Card]) -> EquityResult {
    if let result = PreflopEquityTable.shared?.equity(hero, villain) { return result }
    return exact([hero, villain], board: [])[0]
  }
}
