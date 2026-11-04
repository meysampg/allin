import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ThemeImageIO {
  public enum ImageIOError: Error, Sendable { case cannotCreateDestination(URL), writeFailed(URL) }

  public static func loadImage(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  public static func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw ImageIOError.cannotCreateDestination(url) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ImageIOError.writeFailed(url) }
  }

  /// sRGB, 8 bits per component, premultiplied RGBA, cleared to transparent.
  public static func makeContext(pixelWidth: Int, pixelHeight: Int) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
      data: nil, width: max(pixelWidth, 1), height: max(pixelHeight, 1), bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: max(pixelWidth, 1), height: max(pixelHeight, 1)))
    return context
  }
}
