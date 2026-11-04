import Testing

@testable import TableKit

@MainActor @Suite struct AnimationQueueTests {
  private final class Recorder {
    var values: [Int] = []
  }

  @Test func jobsRunInOrder() async {
    let queue = AnimationQueue(driver: .immediate)
    let recorder = Recorder()
    for index in 0..<50 {
      queue.enqueue { recorder.values.append(index) }
    }
    #expect(queue.pendingCount > 0)
    await queue.waitUntilIdle()
    #expect(recorder.values == Array(0..<50))
    #expect(queue.isIdle && queue.pendingCount == 0)
  }

  @Test func waitingOnAnIdleQueueReturns() async {
    let queue = AnimationQueue(driver: .spriteKit)
    #expect(queue.isIdle)
    await queue.waitUntilIdle()
  }

  @Test func cancelDropsPendingJobs() async {
    let queue = AnimationQueue(driver: .immediate)
    let recorder = Recorder()
    for index in 0..<10 { queue.enqueue { recorder.values.append(index) } }
    queue.cancelAll()
    #expect(queue.pendingCount == 0)
    await queue.waitUntilIdle()
    #expect(recorder.values.isEmpty)
    queue.enqueue { recorder.values.append(99) }
    await queue.waitUntilIdle()
    #expect(recorder.values == [99])
  }

  @Test func suspendingJobsStillFinishInOrder() async {
    let queue = AnimationQueue(driver: .spriteKit)
    let recorder = Recorder()
    for index in 0..<5 {
      queue.enqueue {
        try? await Task.sleep(for: .milliseconds(5))
        recorder.values.append(index)
      }
    }
    await queue.waitUntilIdle()
    #expect(recorder.values == [0, 1, 2, 3, 4])
  }
}
