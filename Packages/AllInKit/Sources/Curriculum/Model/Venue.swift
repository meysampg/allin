import Foundation

public struct VenueHost: Codable, Sendable, Hashable {
  public let name: String
  public let line: String
  public let artKey: String?

  public init(name: String, line: String, artKey: String? = nil) {
    self.name = name
    self.line = line
    self.artKey = artKey
  }
}

public struct VenueMeter: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let name: String
  public let skills: [String]

  public init(id: String, name: String, skills: [String]) {
    self.id = id
    self.name = name
    self.skills = skills
  }
}

public enum NodeKind: String, ContentEnum { case lesson, drill, table, boss }

public struct NodeUnlock: Codable, Sendable, Hashable {
  public let after: [String]

  public init(after: [String]) { self.after = after }
}

public enum TableFormat: String, ContentEnum {
  case cash6, headsUp

  /// Opponents needed at the table.
  public var opponentCount: Int { self == .cash6 ? 5 : 1 }
}

public enum TableCoachSetting: String, ContentEnum { case questions, review, off }

public struct TableSessionSpec: Codable, Sendable, Hashable {
  public let format: TableFormat
  public let opponents: [String]
  public let hands: Int
  public let blinds: Blinds
  public let stackBB: Int
  public let coach: TableCoachSetting

  public init(
    format: TableFormat, opponents: [String], hands: Int, blinds: Blinds, stackBB: Int,
    coach: TableCoachSetting = .questions
  ) {
    self.format = format
    self.opponents = opponents
    self.hands = hands
    self.blinds = blinds
    self.stackBB = stackBB
    self.coach = coach
  }

  private enum CodingKeys: String, CodingKey { case format, opponents, hands, blinds, stackBB, coach }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      format: try c.decode(TableFormat.self, forKey: .format),
      opponents: try c.decode([String].self, forKey: .opponents),
      hands: try c.decode(Int.self, forKey: .hands),
      blinds: try c.decode(Blinds.self, forKey: .blinds),
      stackBB: try c.decode(Int.self, forKey: .stackBB),
      coach: try c.decodeIfPresent(TableCoachSetting.self, forKey: .coach) ?? .questions)
  }
}

public struct VenueNode: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let kind: NodeKind
  public let title: String?
  public let lesson: String?
  public let drill: String?
  public let boss: String?
  public let table: TableSessionSpec?
  /// As authored; nil means "after the previous node".
  public let unlock: NodeUnlock?

  public init(
    id: String, kind: NodeKind, title: String? = nil, lesson: String? = nil, drill: String? = nil,
    boss: String? = nil, table: TableSessionSpec? = nil, unlock: NodeUnlock? = nil
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.lesson = lesson
    self.drill = drill
    self.boss = boss
    self.table = table
    self.unlock = unlock
  }

  private enum CodingKeys: String, CodingKey { case id, kind, title, lesson, drill, boss, table, unlock }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try c.decode(NodeKind.self, forKey: .kind)
    self.init(
      id: try c.decode(String.self, forKey: .id), kind: kind,
      title: try c.decodeIfPresent(String.self, forKey: .title),
      lesson: try c.decodeIfPresent(String.self, forKey: .lesson),
      drill: try c.decodeIfPresent(String.self, forKey: .drill),
      boss: try c.decodeIfPresent(String.self, forKey: .boss),
      table: try c.decodeIfPresent(TableSessionSpec.self, forKey: .table),
      unlock: try c.decodeIfPresent(NodeUnlock.self, forKey: .unlock))
    let present: [(String, Bool)] = [
      ("lesson", lesson != nil), ("drill", drill != nil), ("boss", boss != nil), ("table", table != nil),
    ]
    guard present.contains(where: { $0.0 == kind.rawValue && $0.1 }) else {
      throw corrupted(decoder, "node of kind \(kind.rawValue) needs '\(kind.rawValue)'")
    }
    if let extra = present.first(where: { $0.0 != kind.rawValue && $0.1 }) {
      throw corrupted(decoder, "node of kind \(kind.rawValue) cannot have '\(extra.0)'")
    }
  }
}

public struct Venue: Codable, Sendable, Hashable, Identifiable {
  public let schemaVersion: Int
  public let id: String
  public let name: String
  public let place: String?
  public let chapter: String
  public let host: VenueHost
  public let meters: [VenueMeter]
  public let nodes: [VenueNode]

  public init(
    schemaVersion: Int = ContentSchema.version, id: String, name: String, place: String? = nil,
    chapter: String = "", host: VenueHost, meters: [VenueMeter] = [], nodes: [VenueNode]
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.place = place
    self.chapter = chapter
    self.host = host
    self.meters = meters
    self.nodes = nodes
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, id, name, place, chapter, host, meters, nodes
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), id: try c.decode(String.self, forKey: .id),
      name: try c.decode(String.self, forKey: .name), place: try c.decodeIfPresent(String.self, forKey: .place),
      chapter: try c.decodeIfPresent(String.self, forKey: .chapter) ?? "",
      host: try c.decode(VenueHost.self, forKey: .host),
      meters: try c.decodeIfPresent([VenueMeter].self, forKey: .meters) ?? [],
      nodes: try c.decode([VenueNode].self, forKey: .nodes))
  }

  public func node(_ id: String) -> VenueNode? { nodes.first { $0.id == id } }

  /// The nodes that must be completed before `node` unlocks: `unlock.after`, else the previous node.
  public func prerequisites(of node: VenueNode) -> [String] {
    if let unlock = node.unlock { return unlock.after }
    guard let index = nodes.firstIndex(where: { $0.id == node.id }), index > 0 else { return [] }
    return [nodes[index - 1].id]
  }
}
