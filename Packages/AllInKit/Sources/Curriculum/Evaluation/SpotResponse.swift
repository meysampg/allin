import Foundation
import PokerCore
import PokerEquity

/// What a player answers to a spot.
public enum SpotResponse: Sendable, Hashable {
  case option(String)
  case options(Set<String>)
  case cards([Card])
  case number(Int)
  case range(HandRange)
}

/// One choice of an option question.
public struct AnswerOption: Sendable, Hashable, Identifiable {
  /// Action tokens "fold", "call", "bet:0.5"; "seat:3"; "split"; bucket id; HandCategoryName; "size:120".
  public let id: String
  /// ActionLabel.long, a seat name, "Split", a bucket label, a category title or "Raise to 120".
  public let label: String
  /// Expected value in big blinds (EV methods).
  public let evBB: Double?

  public init(id: String, label: String, evBB: Double? = nil) {
    self.id = id
    self.label = label
    self.evBB = evBB
  }
}
