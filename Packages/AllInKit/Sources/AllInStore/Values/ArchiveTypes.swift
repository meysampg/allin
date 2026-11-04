import Foundation
import PokerCore

public enum SessionKind: String, Codable, Sendable, CaseIterable {
  case career, quick, arena, boss, exam
}

public struct SessionTotals: Codable, Sendable, Hashable {
  public var hands: Int
  public var decisionScore: Double?
  public var netChips: Int
  public var luckChips: Double
  public var assisted: Bool

  public init(hands: Int, decisionScore: Double? = nil, netChips: Int, luckChips: Double = 0, assisted: Bool = false) {
    self.hands = hands
    self.decisionScore = decisionScore
    self.netChips = netChips
    self.luckChips = luckChips
    self.assisted = assisted
  }
}

/// `"<session uuid>#<hand id>"`: the unique key of an archived hand.
public struct ArchiveKey: Hashable, Sendable, Codable, CustomStringConvertible {
  public let sessionID: UUID
  public let handID: HandID

  public init(sessionID: UUID, handID: HandID) {
    self.sessionID = sessionID
    self.handID = handID
  }

  public init?(rawValue: String) {
    let parts = rawValue.split(separator: "#", omittingEmptySubsequences: false)
    guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let hand = UInt64(parts[1]) else {
      return nil
    }
    self.init(sessionID: id, handID: HandID(hand))
  }

  public var rawValue: String { "\(sessionID.uuidString)#\(handID.rawValue)" }
  public var description: String { rawValue }

  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let key = ArchiveKey(rawValue: raw) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Bad archive key \(raw)"))
    }
    self = key
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct ArchivedSeat: Codable, Sendable, Hashable {
  public let seat: Int
  public let name: String
  public let characterID: String?
  public let style: String?
  public let isHero: Bool

  public init(seat: Int, name: String, characterID: String? = nil, style: String? = nil, isHero: Bool = false) {
    self.seat = seat
    self.name = name
    self.characterID = characterID
    self.style = style
    self.isHero = isHero
  }
}

public struct HandGradeSummary: Codable, Sendable, Hashable {
  public var good: Int
  public var smallMiss: Int
  public var leak: Int
  public var evLossBB: Double
  public var luckChips: Double
  public var weightedQuality: Double
  public var weight: Double
  public var decisionScore: Double?

  public init(
    good: Int, smallMiss: Int, leak: Int, evLossBB: Double, luckChips: Double, weightedQuality: Double,
    weight: Double, decisionScore: Double? = nil
  ) {
    self.good = good
    self.smallMiss = smallMiss
    self.leak = leak
    self.evLossBB = evLossBB
    self.luckChips = luckChips
    self.weightedQuality = weightedQuality
    self.weight = weight
    self.decisionScore = decisionScore
  }
}

public struct ArchivedHandInput: Sendable {
  public var key: ArchiveKey
  public var playedAt: Date
  public var heroSeat: Int
  public var seats: [ArchivedSeat]
  public var log: EventLog
  public var strategySeed: UInt64
  public var netChips: Int
  public var potTotal: Int
  public var bigBlind: Int

  public init(
    key: ArchiveKey, playedAt: Date, heroSeat: Int, seats: [ArchivedSeat], log: EventLog, strategySeed: UInt64,
    netChips: Int, potTotal: Int, bigBlind: Int
  ) {
    self.key = key
    self.playedAt = playedAt
    self.heroSeat = heroSeat
    self.seats = seats
    self.log = log
    self.strategySeed = strategySeed
    self.netChips = netChips
    self.potTotal = potTotal
    self.bigBlind = bigBlind
  }
}

public struct ArchivedHand: Sendable, Hashable {
  public let key: ArchiveKey
  public let playedAt: Date
  public let heroSeat: Int
  public let seats: [ArchivedSeat]
  public let log: EventLog
  public let strategySeed: UInt64
  public let netChips: Int
  public let potTotal: Int
  public let bigBlind: Int
  public let grades: HandGradeSummary?
  public let analysis: Data?

  public init(
    key: ArchiveKey, playedAt: Date, heroSeat: Int, seats: [ArchivedSeat], log: EventLog, strategySeed: UInt64,
    netChips: Int, potTotal: Int, bigBlind: Int, grades: HandGradeSummary?, analysis: Data?
  ) {
    self.key = key
    self.playedAt = playedAt
    self.heroSeat = heroSeat
    self.seats = seats
    self.log = log
    self.strategySeed = strategySeed
    self.netChips = netChips
    self.potTotal = potTotal
    self.bigBlind = bigBlind
    self.grades = grades
    self.analysis = analysis
  }
}

public struct StoredHandSummary: Codable, Sendable, Hashable, Identifiable {
  public let key: ArchiveKey
  public let playedAt: Date
  public let heroSeat: Int
  public let netChips: Int
  public let potTotal: Int
  public let bigBlind: Int
  public let grades: HandGradeSummary?

  public var id: String { key.rawValue }

  public init(
    key: ArchiveKey, playedAt: Date, heroSeat: Int, netChips: Int, potTotal: Int, bigBlind: Int,
    grades: HandGradeSummary?
  ) {
    self.key = key
    self.playedAt = playedAt
    self.heroSeat = heroSeat
    self.netChips = netChips
    self.potTotal = potTotal
    self.bigBlind = bigBlind
    self.grades = grades
  }
}
