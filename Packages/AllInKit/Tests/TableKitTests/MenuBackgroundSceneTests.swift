import SpriteKit
import Testing
import ThemeKit

@testable import TableKit

@MainActor @Suite struct MenuBackgroundSceneTests {
  private let size = CGSize(width: 1120, height: 700)

  private func positions(_ scene: MenuBackgroundScene) -> [CGPoint] { scene.driftingNodes.map(\.position) }

  @Test func sameSeedSamePositions() {
    let a = MenuBackgroundScene(size: size, resolver: .codeDrawn, reduceMotion: false, seed: 7)
    let b = MenuBackgroundScene(size: size, resolver: .codeDrawn, reduceMotion: false, seed: 7)
    #expect(positions(a) == positions(b))
  }

  @Test func differentSeedDifferentPositions() {
    let a = MenuBackgroundScene(size: size, resolver: .codeDrawn, reduceMotion: false, seed: 7)
    let b = MenuBackgroundScene(size: size, resolver: .codeDrawn, reduceMotion: false, seed: 8)
    #expect(positions(a) != positions(b))
  }

  @Test func nodeBudget() {
    let scene = MenuBackgroundScene(size: size, resolver: .codeDrawn, reduceMotion: false)
    #expect(scene.driftingNodes.count == 24)
    #expect(scene.children.count <= 60)
  }

  @Test func reduceMotionHasNoActions() {
    let still = MenuBackgroundScene(size: size, resolver: .codeDrawn, reduceMotion: true)
    #expect(still.driftingNodes.allSatisfy { !$0.hasActions() })
    let moving = MenuBackgroundScene(size: size, resolver: .codeDrawn, reduceMotion: false)
    #expect(moving.driftingNodes.contains { $0.hasActions() })
  }
}
