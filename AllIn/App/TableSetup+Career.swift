import Curriculum

extension TableSetup {
  /// A career table session. The hand limit of the spec is not enforced yet.
  static func career(_ spec: TableSessionSpec, seed: UInt64) -> TableSetup {
    let format: Format = spec.format == .headsUp ? .headsUp : .cash6Max
    var setup = TableSetup(
      opponentIDs: resolveOpponents(format: format, selected: spec.opponents, randomMix: false, seed: seed),
      seed: seed)
    setup.format = format
    setup.smallBlind = spec.blinds.small
    setup.bigBlind = spec.blinds.big
    setup.buyIn = spec.stackBB * spec.blinds.big
    switch spec.coach {
    case .questions: setup.coach = .questions
    case .review: setup.coach = .review
    case .off: setup.coach = .off
    }
    return setup
  }
}
