import SwiftUI

/// Published by the table screen via `.focusedSceneValue(\.tableActions, ...)`; driven by the Table menu.
struct TableActions {
  var fold: (@MainActor () -> Void)?
  var checkCall: (@MainActor () -> Void)?
  var raise: (@MainActor () -> Void)?
  var confirm: (@MainActor () -> Void)?
  var hint: (@MainActor () -> Void)?
  var nextHand: (@MainActor () -> Void)?
  var lastHand: (@MainActor () -> Void)?
  var tableMenu: (@MainActor () -> Void)?
  /// +1 / -1
  var sizeStep: (@MainActor (Int) -> Void)?
  /// 1...5
  var preset: (@MainActor (Int) -> Void)?
}

extension FocusedValues {
  @Entry var tableActions: TableActions?
}
