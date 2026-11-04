import Testing

@testable import TableKit

@Suite struct AnimationTimingTests {
  @Test func turboIsFasterThanNormalFasterThanRelaxed() {
    let turbo = AnimationTiming(speedFactor: 0.3)
    let normal = AnimationTiming(speedFactor: 1)
    let relaxed = AnimationTiming(speedFactor: 1.4)
    for beat in AnimationBeat.allCases {
      #expect(turbo.duration(beat) < normal.duration(beat), "\(beat)")
      #expect(normal.duration(beat) < relaxed.duration(beat), "\(beat)")
    }
  }

  @Test func baseDurationsMatchTheContract() {
    let timing = AnimationTiming()
    #expect(timing.duration(.dealCard) == 0.09)
    #expect(timing.duration(.flip) == 0.18)
    #expect(timing.duration(.award) == 0.60)
    #expect(timing.duration(.handEndPause) == 0.80)
    #expect(timing.dealTravel == 0.25)
  }

  @Test func reduceMotionTurnsMovesIntoCrossfadesAndFlipsIntoNothing() {
    let timing = AnimationTiming(speedFactor: 1, reduceMotion: true)
    #expect(timing.duration(.flip) == 0)
    let moves: [AnimationBeat] = [.dealCard, .chipSlide, .collect, .boardSlide, .showdownLift, .award, .fold]
    for beat in moves { #expect(timing.duration(beat) == timing.duration(.crossfade), "\(beat)") }
  }
}
