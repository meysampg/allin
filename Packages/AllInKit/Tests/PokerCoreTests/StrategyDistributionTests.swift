import Testing

@testable import PokerCore

@Suite struct StrategyDistributionTests {
  /// Facing a bet of 100 with 1000 behind and nothing in: raise range 200...1000.
  private func facingBet(chipUnit: Int = 5) -> LegalActions {
    LegalActions.compute(
      seat: 1, stack: 1000, committed: 0, currentBet: 100, lastRaiseSize: 100, canRaise: true,
      chipUnit: chipUnit)
  }

  private func opening() -> LegalActions {
    LegalActions.compute(
      seat: 1, stack: 500, committed: 0, currentBet: 0, lastRaiseSize: 100, canRaise: true, chipUnit: 25)
  }

  @Test func normalizes() throws {
    let d = try ActionDistribution(
      weights: [(.fold, 1), (.call, 2), (.raise(to: 300), 1)], legal: facingBet())
    #expect(abs(d.entries.map(\.probability).reduce(0, +) - 1) < 1e-12)
    #expect(abs(d.probability(of: .call) - 0.5) < 1e-12)
    try d.validate(against: facingBet())
  }

  @Test func mergesDuplicatesAndDropsZeroWeights() throws {
    let d = try ActionDistribution(
      weights: [(.call, 1), (.call, 1), (.fold, 0)], legal: facingBet())
    #expect(d.actions == [.call])
    #expect(d.probability(of: .fold) == 0)
  }

  @Test func rejectsIllegalActions() {
    let legal = facingBet()
    #expect(throws: DistributionError.illegal(.check)) {
      try ActionDistribution(weights: [(.check, 1)], legal: legal)
    }
    #expect(throws: DistributionError.illegal(.bet(to: 300))) {
      try ActionDistribution(weights: [(.bet(to: 300), 1)], legal: legal)
    }
    #expect(throws: DistributionError.illegal(.raise(to: 150))) {  // below the minimum raise
      try ActionDistribution(weights: [(.raise(to: 150), 1)], legal: legal)
    }
    #expect(throws: DistributionError.illegal(.raise(to: 203))) {  // not a multiple of the chip unit
      try ActionDistribution(weights: [(.raise(to: 203), 1)], legal: legal)
    }
    #expect(throws: DistributionError.illegal(.raise(to: 2000))) {  // above the stack
      try ActionDistribution(weights: [(.raise(to: 2000), 1)], legal: legal)
    }
  }

  @Test func rejectsBadWeights() {
    let legal = facingBet()
    #expect(throws: DistributionError.empty) { try ActionDistribution(weights: [], legal: legal) }
    #expect(throws: DistributionError.zeroTotal) {
      try ActionDistribution(weights: [(.fold, 0), (.call, 0)], legal: legal)
    }
    #expect(throws: DistributionError.invalidWeight(.fold)) {
      try ActionDistribution(weights: [(.fold, -1)], legal: legal)
    }
    #expect(throws: DistributionError.invalidWeight(.fold)) {
      try ActionDistribution(weights: [(.fold, .nan)], legal: legal)
    }
  }

  @Test func validateAgainstOtherLegalSetCatchesIllegal() throws {
    let d = try ActionDistribution(weights: [(.call, 1)], legal: facingBet())
    #expect(throws: DistributionError.illegal(.call)) { try d.validate(against: opening()) }
  }

  @Test func raiseToStackIsAllIn() throws {
    let legal = facingBet()
    let d = try ActionDistribution(weights: [(.raise(to: 1000), 1), (.allIn, 1)], legal: legal)
    #expect(d.actions == [.allIn])
    #expect(d.probability(of: .raise(to: 1000)) == 1)
  }

  @Test func snapClampsAndRoundsToChipUnit() {
    let legal = facingBet()  // raise range 200...1000, unit 5
    #expect(ActionDistribution.snapRaise(to: 1, legal: legal) == .raise(to: 200))
    #expect(ActionDistribution.snapRaise(to: 203, legal: legal) == .raise(to: 205))
    #expect(ActionDistribution.snapRaise(to: 202, legal: legal) == .raise(to: 200))
    #expect(ActionDistribution.snapRaise(to: 5000, legal: legal) == .allIn)
    let open = opening()  // bet range 100...500, unit 25
    #expect(ActionDistribution.snapRaise(to: 160, legal: open) == .bet(to: 150))
    #expect(ActionDistribution.snapRaise(to: 163, legal: open) == .bet(to: 175))
    #expect(ActionDistribution.snapRaise(to: 480, legal: open) == .bet(to: 475))
    #expect(ActionDistribution.snapRaise(to: 490, legal: open) == .allIn)
    for amount in stride(from: -50, through: 700, by: 7) {
      let a = ActionDistribution.snapRaise(to: amount, legal: open)!
      #expect(open.isLegal(a), "snap(\(amount)) = \(a)")
    }
  }

  @Test func snapReturnsNilWhenNoRaise() {
    let legal = LegalActions.compute(
      seat: 0, stack: 50, committed: 0, currentBet: 100, lastRaiseSize: 100, canRaise: true)
    #expect(ActionDistribution.snapRaise(to: 200, legal: legal) == nil)
  }

  @Test func snapHandlesOffUnitMinimum() {
    // An incomplete all-in left the bet at 103 (unit 5): minimum raise is 203, which is not a multiple.
    let legal = LegalActions.compute(
      seat: 0, stack: 1000, committed: 0, currentBet: 103, lastRaiseSize: 100, canRaise: true,
      chipUnit: 5)
    let a = ActionDistribution.snapRaise(to: 203, legal: legal)!
    #expect(a == .raise(to: 205))
    for amount in 150...260 {
      #expect(legal.isLegal(ActionDistribution.snapRaise(to: amount, legal: legal)!))
    }
  }

  @Test func potSizedRaisesAreLegalAndUnique() {
    let legal = facingBet()
    let sizes = ActionDistribution.potSizedRaises(fractions: [0.01, 0.5, 1, 100], pot: 300, legal: legal)
    #expect(sizes.allSatisfy(legal.isLegal))
    #expect(Set(sizes).count == sizes.count)
    #expect(sizes.last == .allIn)
    #expect(sizes.first == .raise(to: 200))
  }

  @Test func samplingIsDeterministicPerSeed() throws {
    let d = try ActionDistribution(
      weights: [(.fold, 1), (.call, 2), (.raise(to: 300), 1), (.allIn, 0.5)], legal: facingBet())
    var a = SeededRNG(seed: 42)
    var b = SeededRNG(seed: 42)
    let s1 = (0..<200).map { _ in d.sample(using: &a) }
    let s2 = (0..<200).map { _ in d.sample(using: &b) }
    #expect(s1 == s2)
    var c = SeededRNG(seed: 43)
    #expect((0..<200).map { _ in d.sample(using: &c) } != s1)
  }

  @Test func samplingFollowsProbabilities() throws {
    let d = try ActionDistribution(weights: [(.fold, 1), (.call, 3)], legal: facingBet())
    var rng = SeededRNG(seed: 7)
    let n = 20_000
    let calls = (0..<n).filter { _ in d.sample(using: &rng) == .call }.count
    #expect(abs(Double(calls) / Double(n) - 0.75) < 0.02)
  }

  @Test func samplingNeverReturnsZeroProbabilityAction() throws {
    let d = try ActionDistribution(certain: .call, legal: facingBet())
    var rng = SeededRNG(seed: 1)
    #expect((0..<100).allSatisfy { _ in d.sample(using: &rng) == .call })
  }

  @Test func uniformStrategyIsLegalAndUniform() throws {
    let step = try HandReducer.start(
      config: try TableConfig(seatCount: 4, smallBlind: 50, bigBlind: 100), button: 0,
      stacks: (0..<4).map { SeatStack(seat: $0, stack: 5000) }, seed: 3)
    let seat = step.state.seatToAct!
    let ctx = DecisionContext.make(from: step.state, for: seat)!
    let d = UniformRandomStrategy().distribution(for: ctx)
    try d.validate(against: ctx.legal)
    #expect(d.entries.count >= 4)
    let p = d.entries[0].probability
    #expect(d.entries.allSatisfy { abs($0.probability - p) < 1e-12 })
    #expect(d.actions.contains(.fold) && d.actions.contains(.call) && d.actions.contains(.allIn))
  }
}
