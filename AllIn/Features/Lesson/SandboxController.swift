import Curriculum
import Foundation
import Observation
import PokerCore
import PokerEquity
import os

/// State of the Alchemist's Bench: the editable spot, instant readings and a live, progressive chance.
@MainActor @Observable
final class SandboxController {
  let setup: SandboxSetup
  private(set) var state: SandboxState
  private(set) var readings: SandboxReadings
  /// Hero equity against the tracked range, 0...1; nil until the first estimate arrives.
  private(set) var chance: Double?
  /// True while more samples are still coming in.
  private(set) var isRefining = false
  /// Milliseconds from the last change to its first estimate (diagnostics).
  private(set) var firstEstimateMillis: Double?

  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var started = false

  init(setup: SandboxSetup) {
    self.setup = setup
    self.state = setup.initial
    self.readings = SandboxCalculator.readings(setup.initial, meters: setup.meters)
  }

  var betStep: Int { max(state.bigBlind, 1) }

  /// Starts the first chance estimate. Safe to call again.
  func start() {
    guard !started else { return }
    started = true
    restartChance()
  }

  func stop() {
    task?.cancel()
    task = nil
    generation += 1
    started = false
    isRefining = false
  }

  func setBet(_ value: Int) {
    let range = state.betRange
    let clamped = min(max(value, range.lowerBound), range.upperBound)
    guard clamped != state.villainBet else { return }
    state.villainBet = clamped
    readings = SandboxCalculator.readings(state, meters: setup.meters)
  }

  func setCard(_ slot: SandboxSlot, to card: Card) {
    let next = SandboxCalculator.setting(slot, to: card, in: state)
    guard next != state else { return }
    state = next
    readings = SandboxCalculator.readings(state, meters: setup.meters)
    restartChance()
  }

  /// Cards that cannot be picked for `slot`: everything in use except the card in the slot itself.
  func dead(excluding slot: SandboxSlot) -> CardSet {
    var cards = state.heroCards + state.board
    switch slot {
    case .hero(let i): if state.heroCards.indices.contains(i) { cards.remove(at: i) }
    case .board(let i):
      let index = state.heroCards.count + i
      if state.board.indices.contains(i) { cards.remove(at: index) }
    }
    return CardSet(cards)
  }

  private func restartChance() {
    task?.cancel()
    generation += 1
    let token = generation
    let snapshot = state
    let seed = setup.seed
    guard snapshot.heroCards.count == 2, Set(snapshot.heroCards).count == 2 else {
      chance = nil
      isRefining = false
      return
    }
    isRefining = true
    let began = ContinuousClock.now
    task = Task.detached(priority: .userInitiated) { [weak self] in
      var first = true
      for await estimate in SandboxCalculator.chance(snapshot, seed: seed) {
        if Task.isCancelled { return }
        guard let equity = estimate.results.first?.equity, estimate.samples > 0 else { continue }
        let elapsed = ContinuousClock.now - began
        let millis = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        await self?.receive(
          equity, final: estimate.isFinal, millis: first ? millis : nil, generation: token)
        first = false
      }
      await self?.finish(generation: token)
    }
  }

  private func receive(_ equity: Double, final: Bool, millis: Double?, generation token: Int) {
    guard token == generation else { return }
    chance = equity
    if final { isRefining = false }
    if let millis {
      firstEstimateMillis = millis
      #if DEBUG
        let log = Logger(subsystem: "app.allin", category: "sandbox")
        log.debug("first chance estimate \(millis, format: .fixed(precision: 2)) ms")
      #endif
    }
  }

  private func finish(generation token: Int) {
    guard token == generation else { return }
    isRefining = false
  }
}
