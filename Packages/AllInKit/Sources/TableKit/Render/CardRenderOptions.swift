import CoreGraphics

/// Options for drawing cards: the pixel size of every image and the two-color or four-color deck.
public struct CardRenderOptions: Sendable, Hashable {
  public var pixelSize: CGSize
  public var fourColor: Bool

  /// Texture size for on-table cards: at least 3x the largest on-screen size (105 pt) at Retina scale, so cards stay
  /// sharp full screen. 350 x 490 px is 36 MB for all 53 textures.
  public static let tablePixelSize = CGSize(width: 350, height: 490)

  public init(pixelSize: CGSize = CGSize(width: 250, height: 350), fourColor: Bool = false) {
    self.pixelSize = pixelSize
    self.fourColor = fourColor
  }
}
