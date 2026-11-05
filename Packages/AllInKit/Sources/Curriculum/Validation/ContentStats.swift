import Foundation

/// Counts for `allin-tool content stats`.
public struct ContentStats: Sendable, Hashable {
  public struct VenueCounts: Sendable, Hashable {
    public let venueID: String
    public let lessons: Int
    public let drills: Int
    public let templates: Int
    public let nodes: Int
  }

  public let templatesPerSkill: [String: Int]
  public let templatesPerMethod: [String: Int]
  public let templatesPerQuestion: [String: Int]
  /// Ten bins: difficulty 0..<0.1 up to 0.9...1.
  public let difficultyHistogram: [Int]
  public let venues: [VenueCounts]

  public init(_ library: ContentLibrary) {
    var skills: [String: Int] = [:]
    var methods: [String: Int] = [:]
    var questions: [String: Int] = [:]
    var bins = [Int](repeating: 0, count: 10)
    for template in library.templates.values {
      skills[template.skill, default: 0] += 1
      methods[template.evaluation.method.rawValue, default: 0] += 1
      questions[template.question.type.rawValue, default: 0] += 1
      bins[min(9, max(0, Int(template.difficulty * 10)))] += 1
    }
    templatesPerSkill = skills
    templatesPerMethod = methods
    templatesPerQuestion = questions
    difficultyHistogram = bins
    venues = library.venues.map { venue in
      func count<T>(_ dictionary: [String: T]) -> Int {
        dictionary.keys.filter { library.venueID(ofContent: $0) == venue.id }.count
      }
      return VenueCounts(
        venueID: venue.id, lessons: count(library.lessons), drills: count(library.drills),
        templates: count(library.templates), nodes: venue.nodes.count)
    }
  }

  public func lines() -> [String] {
    var lines: [String] = []
    func section(_ title: String, _ counts: [String: Int]) {
      lines.append("\(title):")
      for key in counts.keys.sorted() {
        lines.append("  \(key.padding(toLength: 28, withPad: " ", startingAt: 0)) \(counts[key] ?? 0)")
      }
    }
    section("templates per skill", templatesPerSkill)
    section("templates per method", templatesPerMethod)
    section("templates per question type", templatesPerQuestion)
    lines.append("difficulty histogram:")
    let peak = max(1, difficultyHistogram.max() ?? 1)
    for (bin, count) in difficultyHistogram.enumerated() {
      let label = String(format: "%.1f-%.1f", Double(bin) / 10, Double(bin + 1) / 10)
      lines.append("  \(label)  \(String(repeating: "#", count: (count * 30 + peak - 1) / peak)) \(count)")
    }
    lines.append("venues:")
    for venue in venues {
      lines.append(
        "  \(venue.venueID.padding(toLength: 20, withPad: " ", startingAt: 0)) lessons \(venue.lessons)  drills \(venue.drills)  templates \(venue.templates)  nodes \(venue.nodes)"
      )
    }
    return lines
  }
}
