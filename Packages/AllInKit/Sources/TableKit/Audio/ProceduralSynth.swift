import Foundation
import PokerCore
import ThemeKit

/// Deterministic, pure sound synthesis for the code-drawn SFX slots.
public enum ProceduralSynth {
  public static func render(
    _ id: ProceduralID, params: ProceduralParams, sampleRate: Double = 44_100, seed: UInt64
  ) -> AudioClip {
    var rng = SeededRNG(seed: seed)
    var gain = 1.0
    let raw: [Float]
    switch id {
    case .sfxFlick:
      raw = flick(params, sampleRate, &rng)
    case .sfxClink:
      raw = clink(params, sampleRate)
    case .sfxSweep:
      raw = sweep(sampleRate, &rng)
    case .sfxBell:
      raw = bell(params, sampleRate)
    case .sfxTick:
      raw = tick(sampleRate)
      gain = min(max(params.double("gain", default: 1), 0), 1)
    case .sfxThump:
      raw = thump(sampleRate, &rng)
    case .sfxTone:
      raw = tone(params, sampleRate)
    default:
      return AudioClip(samples: [Float](repeating: 0, count: max(1, Int(sampleRate * 0.01))), sampleRate: sampleRate)
    }
    return AudioClip(samples: finish(raw, sampleRate: sampleRate, gain: gain), sampleRate: sampleRate)
  }

  // MARK: - Voices

  private static func count(_ seconds: Double, _ sampleRate: Double) -> Int { max(1, Int(seconds * sampleRate)) }

  private static func noise(_ rng: inout SeededRNG) -> Double { Double.random(in: -1...1, using: &rng) }

  /// One-pole low-pass coefficient for a cutoff.
  private static func alpha(_ cutoff: Double, _ sampleRate: Double) -> Double {
    let c = min(max(cutoff, 10), sampleRate * 0.45)
    return 1 - exp(-2 * Double.pi * c / sampleRate)
  }

  private static func flick(_ p: ProceduralParams, _ sr: Double, _ rng: inout SeededRNG) -> [Float] {
    let pitch = max(0.1, p.double("pitch", default: 1))
    let length = min(max(p.double("length", default: 0.07), 0.005), 1)
    let n = count(length, sr)
    let center = 3_000 * pitch
    let lp = alpha(center * 1.5, sr)
    let hp = alpha(center / 1.5, sr)
    var lpState = 0.0
    var hpState = 0.0
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
      let x = noise(&rng)
      lpState += lp * (x - lpState)
      hpState += hp * (lpState - hpState)
      let band = lpState - hpState
      let env = exp(-5 * Double(i) / Double(n))
      out[i] = Float(band * env)
    }
    return out
  }

  private static func clink(_ p: ProceduralParams, _ sr: Double) -> [Float] {
    let strikes = min(max(Int(p.double("count", default: 1)), 1), 8)
    let spacing = 0.045
    let strikeLength = 0.12
    let n = count(spacing * Double(strikes - 1) + strikeLength, sr)
    var out = [Float](repeating: 0, count: n)
    let carrier = 2_400.0
    let ratio = 1.41
    for s in 0..<strikes {
      let start = Int(spacing * Double(s) * sr)
      let m = count(strikeLength, sr)
      for i in 0..<m where start + i < n {
        let t = Double(i) / sr
        let index = 4 * exp(-t * 40)
        let env = exp(-t * 30)
        let phase = 2 * Double.pi * carrier * t + index * sin(2 * Double.pi * carrier * ratio * t)
        out[start + i] += Float(sin(phase) * env * (1 - 0.1 * Double(s)))
      }
    }
    return out
  }

  private static func sweep(_ sr: Double, _ rng: inout SeededRNG) -> [Float] {
    let n = count(0.35, sr)
    var state = 0.0
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
      let u = Double(i) / Double(n)
      let cutoff = 6_000 * pow(300.0 / 6_000.0, u)
      state += alpha(cutoff, sr) * (noise(&rng) - state)
      out[i] = Float(state * sin(Double.pi * u))
    }
    return out
  }

  private static func bell(_ p: ProceduralParams, _ sr: Double) -> [Float] {
    let notes = min(max(Int(p.double("notes", default: 1)), 1), 8)
    let base = max(20, p.double("base", default: 523))
    let step = 0.12
    let noteLength = 0.6
    let n = count(step * Double(notes - 1) + noteLength, sr)
    var out = [Float](repeating: 0, count: n)
    let partials: [(ratio: Double, amp: Double)] = [(1, 1), (2.0, 0.5), (2.76, 0.3), (5.4, 0.15)]
    let major3 = pow(2.0, 4.0 / 12.0)
    for k in 0..<notes {
      let f0 = base * pow(major3, Double(k))
      let start = Int(step * Double(k) * sr)
      let m = count(noteLength, sr)
      for i in 0..<m where start + i < n {
        let t = Double(i) / sr
        var v = 0.0
        for (j, part) in partials.enumerated() {
          let f = f0 * part.ratio
          if f < sr * 0.45 { v += part.amp * sin(2 * Double.pi * f * t) * exp(-t * (6 + 5 * Double(j))) }
        }
        out[start + i] += Float(v)
      }
    }
    return out
  }

  private static func tick(_ sr: Double) -> [Float] {
    let n = count(0.015, sr)
    return (0..<n).map { i in
      let t = Double(i) / sr
      return Float(sin(2 * Double.pi * 1_800 * t) * exp(-t * 300))
    }
  }

  private static func thump(_ sr: Double, _ rng: inout SeededRNG) -> [Float] {
    let n = count(0.25, sr)
    return (0..<n).map { i in
      let t = Double(i) / sr
      let body = sin(2 * Double.pi * 90 * t) * exp(-t * 18)
      let transient = noise(&rng) * exp(-t * 400) * 0.5
      return Float(body + transient)
    }
  }

  private static func tone(_ p: ProceduralParams, _ sr: Double) -> [Float] {
    let from = max(20, p.double("from", default: 440))
    let to = max(20, p.double("to", default: 440))
    let length = 0.3
    let n = count(length, sr)
    var phase = 0.0
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
      let u = Double(i) / Double(n)
      phase += 2 * Double.pi * (from + (to - from) * u) / sr
      out[i] = Float(sin(phase) * (1 - 0.3 * u))
    }
    return out
  }

  // MARK: - Finishing

  /// Peak-normalizes to 0.9 (times `gain`), then applies a short fade-in and fade-out.
  private static func finish(_ raw: [Float], sampleRate: Double, gain: Double) -> [Float] {
    var out = raw
    let peak = out.reduce(Float(0)) { max($0, abs($1)) }
    if peak > 0 {
      let scale = Float(0.9 * gain) / peak
      for i in out.indices { out[i] *= scale }
    }
    let fadeIn = min(max(1, Int(0.002 * sampleRate)), out.count / 4)
    let fadeOut = min(max(1, Int(0.005 * sampleRate)), out.count / 4)
    for i in 0..<fadeIn { out[i] *= Float(i) / Float(fadeIn) }
    for i in 0..<fadeOut { out[out.count - 1 - i] *= Float(i) / Float(fadeOut) }
    return out
  }
}
