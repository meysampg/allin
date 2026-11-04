import SwiftUI

public struct TagOption<Value: Hashable>: Identifiable {
  public let value: Value
  public let label: String
  public let id: String

  public init(_ value: Value, label: String, id: String) {
    self.value = value
    self.label = label
    self.id = id
  }
}

public struct TagPicker<Value: Hashable>: View {
  private let options: [TagOption<Value>]
  private let selection: Binding<Value>
  private let idPrefix: String?

  public init(options: [TagOption<Value>], selection: Binding<Value>, idPrefix: String? = nil) {
    self.options = options
    self.selection = selection
    self.idPrefix = idPrefix
  }

  public var body: some View {
    HStack(spacing: 6) {
      ForEach(options) { option in
        let selected = selection.wrappedValue == option.value
        Button {
          selection.wrappedValue = option.value
        } label: {
          Tag(option.label, style: selected ? .dark : .plain)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier(for: option))
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }

  private func identifier(for option: TagOption<Value>) -> String {
    if let idPrefix { return "\(idPrefix).\(option.id)" }
    return option.id
  }
}
