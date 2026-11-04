import PokerCore
import SwiftUI
import Testing

@testable import AllInUI

@MainActor
@Suite struct ComponentRenderTests {
  private func renders<V: View>(_ view: V) -> Bool {
    let renderer = ImageRenderer(content: view.allInTheme(.hearthwood))
    renderer.scale = 1
    guard let image = renderer.cgImage else { return false }
    return image.width > 0 && image.height > 0
  }

  @Test func cardViews() throws {
    #expect(renders(CardView(card: try Card("Qs"))))
    #expect(renders(CardView(card: nil)))
    #expect(renders(CardView(card: try Card("Td"), faceDown: true, size: .small)))
    #expect(renders(CardView(card: try Card("2c"), size: .width(80), fourColor: true)))
  }

  @Test func avatars() {
    #expect(renders(AvatarMedallion(characterID: "grumli", name: "Grumli")))
    #expect(renders(AvatarMedallion(characterID: "nobody-here", mood: .think, isDimmed: true)))
    #expect(renders(AvatarMedallion(characterID: nil)))
  }

  @Test func smallComponents() {
    #expect(renders(Tag("Hello", systemImage: "star", style: .gold)))
    #expect(renders(Meter(value: 0.5, label: "Strength").frame(width: 120)))
    #expect(renders(StarRow(filled: 2)))
    #expect(renders(ParchmentPanel(title: "Title") { Text("Body") }.frame(width: 200)))
    #expect(renders(Button("Go") {}.buttonStyle(.fantasy(.primary))))
  }

  @Test func tagPicker() {
    var value = "a"
    let binding = Binding(get: { value }, set: { value = $0 })
    let options = [TagOption("a", label: "A", id: "a"), TagOption("b", label: "B", id: "b")]
    #expect(renders(TagPicker(options: options, selection: binding, idPrefix: "x")))
  }
}
