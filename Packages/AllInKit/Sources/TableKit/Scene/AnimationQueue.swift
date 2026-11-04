import Foundation

/// Plays animation jobs one after another, in the order they were enqueued.
@MainActor public final class AnimationQueue {
  public enum Driver: Sendable {
    /// Real SKActions.
    case spriteKit
    /// Skip actions and apply end states (tests, headless).
    case immediate
  }

  public let driver: Driver

  private var pending: [@MainActor () async -> Void] = []
  private var isRunning = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init(driver: Driver) {
    self.driver = driver
  }

  public func enqueue(_ job: @escaping @MainActor () async -> Void) {
    pending.append(job)
    guard !isRunning else { return }
    isRunning = true
    Task { @MainActor in await self.drain() }
  }

  public var pendingCount: Int { pending.count }

  public var isIdle: Bool { pending.isEmpty && !isRunning }

  /// Returns when every enqueued job has finished (immediately when idle).
  public func waitUntilIdle() async {
    if isIdle { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  /// Drops the jobs that have not started. A running job finishes.
  public func cancelAll() {
    pending.removeAll()
  }

  private func drain() async {
    while !pending.isEmpty {
      let job = pending.removeFirst()
      await job()
    }
    isRunning = false
    let resumed = waiters
    waiters.removeAll()
    for waiter in resumed { waiter.resume() }
  }
}
