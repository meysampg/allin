import CoreGraphics
import Foundation

public enum ImageDigest {
  /// FNV-1a over the RGBA bytes after redrawing into `ThemeImageIO.makeContext`.
  public static func fnv1a(_ image: CGImage) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    withPixels(of: image) { bytes, count in
      for i in 0..<count {
        hash ^= UInt64(bytes[i])
        hash = hash &* 0x100_0000_01b3
      }
    }
    return hash
  }

  /// The share of pixels with alpha > 0.
  public static func opaqueFraction(_ image: CGImage) -> Double {
    var covered = 0
    var total = 0
    withPixels(of: image) { bytes, count in
      total = count / 4
      var i = 3
      while i < count {
        if bytes[i] > 0 { covered += 1 }
        i += 4
      }
    }
    return total == 0 ? 0 : Double(covered) / Double(total)
  }

  private static func withPixels(of image: CGImage, _ body: (UnsafePointer<UInt8>, Int) -> Void) {
    let context = ThemeImageIO.makeContext(pixelWidth: image.width, pixelHeight: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { return }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    // Rows are contiguous only when bytesPerRow equals width * 4; walk by row otherwise.
    let rowBytes = context.width * 4
    if context.bytesPerRow == rowBytes {
      body(UnsafePointer(bytes), rowBytes * context.height)
    } else {
      var packed = [UInt8](repeating: 0, count: rowBytes * context.height)
      for row in 0..<context.height {
        for i in 0..<rowBytes { packed[row * rowBytes + i] = bytes[row * context.bytesPerRow + i] }
      }
      packed.withUnsafeBufferPointer { body($0.baseAddress!, $0.count) }
    }
  }
}
