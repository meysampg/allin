import AllInUI
import PokerCore
import SwiftUI

struct ActionBar: View {
  @Environment(\.theme) private var theme
  let controller: TableController

  private var legal: LegalActions? {
    if case .yourTurn(let legal) = controller.phase { return legal }
    return nil
  }

  var body: some View {
    let legal = legal
    let canRaise = legal.map { $0.raiseRange != nil || $0.canAllIn } ?? false
    HStack(spacing: 10) {
      Button("Fold") { controller.fold() }
        .buttonStyle(.fantasy(.secondary))
        .disabled(legal == nil)
        .accessibilityIdentifier("table.action.fold")
      Button(legal.map(BetSizing.checkCallLabel) ?? "Check") { controller.checkCall() }
        .buttonStyle(.fantasy(.primary))
        .disabled(legal == nil)
        .accessibilityIdentifier("table.action.checkCall")
      raiseButton(canRaise: canRaise)
      HStack(spacing: 4) {
        ForEach(BetPreset.allCases, id: \.self) { preset in
          Button(preset.label) { controller.preset(preset.rawValue) }
            .buttonStyle(.fantasy(.small))
            .disabled(!canRaise)
            .accessibilityIdentifier("table.preset.\(presetID(preset))")
        }
      }
      slider(legal: legal)
      if controller.isRaiseMode, let amount = controller.raiseTo {
        Text("\(amount)")
          .font(theme.bodyFont(size: 14, weight: .bold))
          .foregroundStyle(theme.ink)
          .accessibilityIdentifier("table.raiseAmount")
      }
      Tag("⏱ no timer", style: .muted)
        .accessibilityIdentifier("table.timer")
    }
    .padding(.horizontal, 14)
    .frame(height: 78)
    .frame(maxWidth: .infinity)
    .background(theme.panel)
    .overlay(alignment: .top) { Rectangle().fill(theme.ink.opacity(0.7)).frame(height: 2) }
  }

  private func raiseButton(canRaise: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    let amount = controller.raiseTo.map { "Raise to \($0)" } ?? "Raise"
    return Button(amount) { controller.submitRaise() }
      .buttonStyle(.fantasy(.secondary))
      .overlay(shape.strokeBorder(theme.gold, lineWidth: controller.isRaiseMode ? 4 : 0))
      .shadow(color: controller.isRaiseMode ? theme.gold.opacity(0.7) : .clear, radius: 6)
      .disabled(!canRaise)
      .accessibilityIdentifier("table.action.raise")
  }

  @ViewBuilder
  private func slider(legal: LegalActions?) -> some View {
    if let legal, let range = legal.raiseRange, range.lowerBound < range.upperBound {
      let binding = Binding<Double>(
        get: { Double(controller.raiseTo ?? range.lowerBound) },
        set: { controller.setRaiseTo(Int($0.rounded())) })
      Slider(
        value: binding, in: Double(range.lowerBound)...Double(range.upperBound),
        step: Double(max(1, controller.snapshot.bigBlind))
      )
      .tint(theme.gold)
      .frame(minWidth: 80)
      .accessibilityLabel("Raise size")
      .accessibilityIdentifier("table.slider")
    } else {
      Slider(value: .constant(0), in: 0...1)
        .disabled(true)
        .frame(minWidth: 80)
        .accessibilityLabel("Raise size")
        .accessibilityIdentifier("table.slider")
    }
  }

  private func presetID(_ preset: BetPreset) -> String {
    switch preset {
    case .third: "third"
    case .half: "half"
    case .twoThirds: "twoThirds"
    case .pot: "pot"
    case .allIn: "allIn"
    }
  }
}
