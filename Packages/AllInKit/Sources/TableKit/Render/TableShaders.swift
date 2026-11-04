import Foundation
import SpriteKit
import ThemeKit

public enum TableShaders {
  public static let pulseUniform = "u_pulse"
  public static let colorUniform = "u_rune_color"

  public enum ShaderError: Error, Sendable { case missingResource }

  /// The GLSL source of the rune ring, loaded from the module bundle.
  public static func runesSource() throws -> String {
    guard let url = Bundle.module.url(forResource: "runes", withExtension: "fsh", subdirectory: "Shaders") else {
      throw ShaderError.missingResource
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  @MainActor public static func runes(color: ThemeColor, pulse: Float) -> SKShader {
    let source = (try? runesSource()) ?? fallbackSource
    let rgba = SIMD4<Float>(Float(color.red), Float(color.green), Float(color.blue), Float(color.alpha))
    return SKShader(
      source: source,
      uniforms: [
        SKUniform(name: pulseUniform, float: pulse),
        SKUniform(name: colorUniform, vectorFloat4: rgba),
      ])
  }

  private static let fallbackSource = "void main() { gl_FragColor = texture2D(u_texture, v_tex_coord); }"
}
