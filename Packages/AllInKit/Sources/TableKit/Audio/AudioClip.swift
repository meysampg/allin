/// A mono clip of samples in -1...1.
public struct AudioClip: Sendable, Hashable {
  public let samples: [Float]
  public let sampleRate: Double

  public var duration: Double { Double(samples.count) / sampleRate }

  public init(samples: [Float], sampleRate: Double) {
    self.samples = samples
    self.sampleRate = sampleRate
  }
}
