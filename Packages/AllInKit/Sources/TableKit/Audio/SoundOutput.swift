import AVFoundation
import Foundation
import OSLog

@MainActor
public protocol SoundOutput: AnyObject {
  func play(_ clip: AudioClip, volume: Float)
  func play(fileURL: URL, volume: Float)
}

/// Plays through one AVAudioEngine and a pool of player nodes. The engine starts lazily on the first play.
/// Every failure is logged and swallowed.
@MainActor
public final class AVAudioEngineOutput: SoundOutput {
  private static let poolSize = 4
  private static let sampleRate = 44_100.0

  private let log = Logger(subsystem: "app.allin", category: "audio")
  private var engine: AVAudioEngine?
  private var players: [AVAudioPlayerNode] = []
  private var nextPlayer = 0
  private var fileBuffers: [URL: AVAudioPCMBuffer] = [:]
  private var failedStart = false

  public init() {}

  public func play(_ clip: AudioClip, volume: Float) {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: clip.sampleRate, channels: 1),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.samples.count)),
      let channel = buffer.floatChannelData?[0]
    else { return }
    buffer.frameLength = AVAudioFrameCount(clip.samples.count)
    clip.samples.withUnsafeBufferPointer { src in
      if let base = src.baseAddress { channel.update(from: base, count: src.count) }
    }
    schedule(buffer, volume: volume)
  }

  public func play(fileURL: URL, volume: Float) {
    if let cached = fileBuffers[fileURL] {
      schedule(cached, volume: volume)
      return
    }
    do {
      let file = try AVAudioFile(forReading: fileURL)
      let capacity = AVAudioFrameCount(file.length)
      guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { return }
      try file.read(into: buffer)
      fileBuffers[fileURL] = buffer
      schedule(buffer, volume: volume)
    } catch {
      log.error("could not load sound \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription)")
    }
  }

  private func startEngineIfNeeded() -> Bool {
    if engine != nil { return true }
    if failedStart { return false }
    let engine = AVAudioEngine()
    guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else { return false }
    var nodes: [AVAudioPlayerNode] = []
    for _ in 0..<Self.poolSize {
      let node = AVAudioPlayerNode()
      engine.attach(node)
      engine.connect(node, to: engine.mainMixerNode, format: format)
      nodes.append(node)
    }
    do {
      try engine.start()
    } catch {
      failedStart = true
      log.error("audio engine failed to start: \(error.localizedDescription)")
      return false
    }
    self.engine = engine
    players = nodes
    return true
  }

  private func schedule(_ buffer: AVAudioPCMBuffer, volume: Float) {
    guard startEngineIfNeeded(), let engine, !players.isEmpty else { return }
    if !engine.isRunning {
      do { try engine.start() } catch {
        log.error("audio engine restart failed: \(error.localizedDescription)")
        return
      }
    }
    let node = players[nextPlayer]
    nextPlayer = (nextPlayer + 1) % players.count
    node.stop()
    node.volume = min(max(volume, 0), 1)
    node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    node.play()
  }
}
