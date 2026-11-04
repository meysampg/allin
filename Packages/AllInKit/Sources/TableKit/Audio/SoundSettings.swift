public struct SoundSettings: Sendable, Hashable, Codable {
  public var masterVolume: Float
  public var effectsVolume: Float
  public var isMuted: Bool

  public init(masterVolume: Float = 0.8, effectsVolume: Float = 1, isMuted: Bool = false) {
    self.masterVolume = masterVolume
    self.effectsVolume = effectsVolume
    self.isMuted = isMuted
  }
}
