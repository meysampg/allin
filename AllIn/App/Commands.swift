import SwiftUI

struct AllInCommands: Commands {
  @FocusedValue(\.tableActions) private var actions

  var body: some Commands {
    CommandMenu("Table") {
      Button("Fold") { actions?.fold?() }
        .keyboardShortcut(KeyEquivalent("f"), modifiers: [])
        .disabled(actions?.fold == nil)
      Button("Check / Call") { actions?.checkCall?() }
        .keyboardShortcut(KeyEquivalent("c"), modifiers: [])
        .disabled(actions?.checkCall == nil)
      Button("Raise") { actions?.raise?() }
        .keyboardShortcut(KeyEquivalent("r"), modifiers: [])
        .disabled(actions?.raise == nil)
      Divider()
      Button("Size Up") { actions?.sizeStep?(1) }
        .keyboardShortcut(.upArrow, modifiers: [])
        .disabled(actions?.sizeStep == nil)
      Button("Size Down") { actions?.sizeStep?(-1) }
        .keyboardShortcut(.downArrow, modifiers: [])
        .disabled(actions?.sizeStep == nil)
      ForEach(1...5, id: \.self) { n in
        Button("Preset \(n)") { actions?.preset?(n) }
          .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: [])
          .disabled(actions?.preset == nil)
      }
      Divider()
      Button("Confirm") { actions?.confirm?() }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(actions?.confirm == nil)
      Button("Hint") { actions?.hint?() }
        .keyboardShortcut(KeyEquivalent("h"), modifiers: [])
        .disabled(actions?.hint == nil)
      Button("Next Hand") { actions?.nextHand?() }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(actions?.nextHand == nil)
      Button("Last Hand") { actions?.lastHand?() }
        .keyboardShortcut(KeyEquivalent("l"), modifiers: .command)
        .disabled(actions?.lastHand == nil)
      Button("Table Menu") { actions?.tableMenu?() }
        .keyboardShortcut(.escape, modifiers: [])
        .disabled(actions?.tableMenu == nil)
    }
  }
}
