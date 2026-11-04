import Testing
import ThemeKit

@testable import TableKit

@Suite struct ProceduralSynthTests {
  @Test func everyCodeDrawnEventRendersAUsableClip() {
    for event in SoundEvent.allCases {
      guard case .procedural(let id, let params) = ThemeResolver.codeDrawn.resolve(.sound(event)) else {
        Issue.record("\(event) is not procedural")
        continue
      }
      let clip = ProceduralSynth.render(id, params: params, seed: 7)
      #expect(!clip.samples.isEmpty)
      #expect(clip.duration > 0 && clip.duration <= 3)
      let peak = clip.samples.reduce(Float(0)) { max($0, abs($1)) }
      #expect(peak <= 1)
      #expect(peak > 0, "\(event) rendered silence")
    }
  }

  @Test func sameInputsGiveIdenticalSamples() {
    let a = ProceduralSynth.render(.sfxFlick, params: [:], seed: 3)
    let b = ProceduralSynth.render(.sfxFlick, params: [:], seed: 3)
    #expect(a == b)
  }

  @Test func differentSeedChangesNoise() {
    let a = ProceduralSynth.render(.sfxFlick, params: [:], seed: 3)
    let b = ProceduralSynth.render(.sfxFlick, params: [:], seed: 4)
    #expect(a.samples != b.samples)
  }

  @Test func unknownIdIsShortSilence() {
    let clip = ProceduralSynth.render("sfx.nope", params: [:], seed: 1)
    #expect(clip.duration > 0 && clip.duration < 0.05)
    #expect(clip.samples.allSatisfy { $0 == 0 })
  }

  @Test func bellNotesLengthenTheClip() {
    let one = ProceduralSynth.render(.sfxBell, params: ["notes": 1], seed: 1)
    let three = ProceduralSynth.render(.sfxBell, params: ["notes": 3], seed: 1)
    #expect(three.duration > one.duration)
  }
}
