import Foundation
import Testing
import ThemeKit

@testable import TableKit

@MainActor
private final class RecordingOutput: SoundOutput {
  var clips: [(AudioClip, Float)] = []
  var files: [(URL, Float)] = []
  func play(_ clip: AudioClip, volume: Float) { clips.append((clip, volume)) }
  func play(fileURL: URL, volume: Float) { files.append((fileURL, volume)) }
  var total: Int { clips.count + files.count }
}

@MainActor
@Suite struct SoundBankTests {
  private func bank(_ settings: SoundSettings = SoundSettings(), resolver: ThemeResolver = .codeDrawn)
    -> (SoundBank, RecordingOutput)
  {
    let output = RecordingOutput()
    return (SoundBank(resolver: resolver, settings: settings, output: output), output)
  }

  @Test func playsProceduralClip() {
    let (bank, output) = bank()
    bank.play(.win)
    #expect(output.clips.count == 1)
    #expect(abs(output.clips[0].1 - 0.8) < 1e-6)
  }

  @Test func mutedSendsNothing() {
    let (bank, output) = bank(SoundSettings(isMuted: true))
    bank.play(.win)
    #expect(output.total == 0)
  }

  @Test func zeroMasterSendsNothing() {
    let (bank, output) = bank(SoundSettings(masterVolume: 0))
    bank.play(.uiTap)
    #expect(output.total == 0)
  }

  @Test func volumesMultiply() {
    let (bank, output) = bank(SoundSettings(masterVolume: 0.5, effectsVolume: 0.5))
    bank.play(.uiTap)
    #expect(abs(output.clips[0].1 - 0.25) < 1e-6)
  }

  @Test func settingsAreLive() {
    let (bank, output) = bank()
    bank.settings.isMuted = true
    bank.play(.stamp)
    bank.settings.isMuted = false
    bank.play(.stamp)
    #expect(output.total == 1)
  }

  @Test func filesRoundRobin() {
    let root = URL(fileURLWithPath: "/tmp/soundbank-test.allintheme")
    let manifest = ThemeManifest(
      id: "sfx", name: "SFX", slots: ["sound.win": .init(files: ["a.caf", "b.caf"])])
    let resolver = ThemeResolver(chain: [ThemePack(manifest: manifest, rootURL: root)])
    let (bank, output) = bank(resolver: resolver)
    #expect(bank.clip(for: .win) == nil)
    bank.play(.win)
    bank.play(.win)
    bank.play(.win)
    #expect(output.clips.isEmpty)
    #expect(output.files.map(\.0.lastPathComponent) == ["a.caf", "b.caf", "a.caf"])
  }

  @Test func singleFileSlot() {
    let root = URL(fileURLWithPath: "/tmp/soundbank-test.allintheme")
    let manifest = ThemeManifest(id: "sfx", name: "SFX", slots: ["sound.stamp": .init(file: "s.caf")])
    let resolver = ThemeResolver(chain: [ThemePack(manifest: manifest, rootURL: root)])
    let (bank, output) = bank(resolver: resolver)
    bank.play(.stamp)
    #expect(output.files.map(\.0.lastPathComponent) == ["s.caf"])
  }

  @Test func preloadFillsCache() {
    let (bank, _) = bank()
    bank.preload()
    for event in SoundEvent.allCases { #expect(bank.clip(for: event) != nil) }
    #expect(bank.clip(for: .win) == bank.clip(for: .win))
  }
}
