import SwiftUI

/// Fallback for the Table menu shortcuts: the same keys, mapped to the same idempotent controller methods.
private struct TableKeyHandling: ViewModifier {
  let controller: TableController
  @FocusState private var focused: Bool

  func body(content: Content) -> some View {
    content
      .focusable()
      .focusEffectDisabled()
      .focused($focused)
      .onAppear { focused = true }
      .onKeyPress(phases: .down) { press in handle(press) }
  }

  private func handle(_ press: KeyPress) -> KeyPress.Result {
    guard press.modifiers.isEmpty else { return .ignored }
    switch press.key {
    case .return: controller.confirm()
    case .space: controller.nextHand()
    case .escape: controller.toggleMenu()
    case .upArrow: controller.step(1)
    case .downArrow: controller.step(-1)
    default:
      switch press.characters.lowercased() {
      case "f": controller.fold()
      case "c": controller.checkCall()
      case "r": controller.raise()
      case "1", "2", "3", "4", "5": controller.preset(Int(press.characters) ?? 0)
      default: return .ignored
      }
    }
    return .handled
  }
}

extension View {
  func tableKeyHandling(_ controller: TableController) -> some View {
    modifier(TableKeyHandling(controller: controller))
  }
}
