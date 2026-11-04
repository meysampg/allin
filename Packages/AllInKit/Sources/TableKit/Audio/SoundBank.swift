import Foundation
import ThemeKit

/// Plays theme sound slots: procedural SFX synthesized once and cached, or the slot's files.
@MainActor
public final class SoundBank {
  private let resolver: ThemeResolver
  private let output: any SoundOutput
  private var cache: [SoundEvent: AudioClip] = [:]
  private var roundRobin: [SoundEvent: Int] = [:]

  public var settings: SoundSettings

  public init(resolver: ThemeResolver, settings: SoundSettings = SoundSettings(), output: (any SoundOutput)? = nil) {
    self.resolver = resolver
    self.settings = settings
    self.output = output ?? AVAudioEngineOutput()
  }

  public func play(_ event: SoundEvent) {
    let volume = settings.masterVolume * settings.effectsVolume
    guard !settings.isMuted, volume > 0 else { return }
    switch resolver.resolve(.sound(event)) {
    case .procedural:
      if let clip = clip(for: event) { output.play(clip, volume: volume) }
    case .file(let url):
      output.play(fileURL: url, volume: volume)
    case .files(let urls):
      guard !urls.isEmpty else { return }
      let index = roundRobin[event, default: 0] % urls.count
      roundRobin[event] = (index + 1) % urls.count
      output.play(fileURL: urls[index], volume: volume)
    }
  }

  /// Procedural clips (cached); nil when the slot is file-backed.
  public func clip(for event: SoundEvent) -> AudioClip? {
    if let cached = cache[event] { return cached }
    let slot = AssetSlot.sound(event)
    guard case .procedural(let id, let params) = resolver.resolve(slot) else { return nil }
    let clip = ProceduralSynth.render(id, params: params, seed: Self.fnv1a(slot.id))
    cache[event] = clip
    return clip
  }

  /// Renders every procedural event so the first play has no synthesis cost.
  public func preload() {
    for event in SoundEvent.allCases { _ = clip(for: event) }
  }

  private static func fnv1a(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    return hash
  }
}
