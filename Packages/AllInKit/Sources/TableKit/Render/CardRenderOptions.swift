import CoreGraphics

/// Options for drawing cards: the pixel size of every image and the two-color or four-color deck.
public struct CardRenderOptions: Sendable, Hashable {
  public var pixelSize: CGSize
  public var fourColor: Bool

  public init(pixelSize: CGSize = CGSize(width: 250, height: 350), fourColor: Bool = false) {
    self.pixelSize = pixelSize
    self.fourColor = fourColor
  }
}
