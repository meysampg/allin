import SwiftUI

/// The pot cut into equal slices of the call: pay one slice to win the rest.
public struct PotSlicesModel: Sendable, Hashable {
  /// Pot including the current bets.
  public var pot: Int
  public var call: Int

  public init(pot: Int, call: Int) {
    self.pot = pot
    self.call = call
  }

  public var slices: Int {
    guard call > 0 else { return 2 }
    return max(2, Int((Double(pot + call) / Double(call)).rounded()))
  }

  public var priceNeeded: Double {
    guard call > 0, pot + call > 0 else { return 0 }
    return Double(call) / Double(pot + call)
  }

  public var caption: String {
    guard call > 0 else { return "Checking is free, so you never need to win." }
    let win = slices - 1
    let percent = Int((priceNeeded * 100).rounded())
    return "You pay 1 part to win \(win), so you need to win more than 1 in \(slices) times (\(percent)%)."
  }
}

public struct PotSlicesView: View {
  @Environment(\.theme) private var theme
  private let model: PotSlicesModel

  public init(model: PotSlicesModel) { self.model = model }

  public var body: some View {
    HStack(alignment: .center, spacing: 18) {
      Reveal { p in
        pie(progress: p)
      }
      .frame(width: 132, height: 132)
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Tag("Pot \(model.pot)", style: .gold).accessibilityIdentifier("explainer.potSlices.pot")
          Tag("Call \(model.call)", style: .dark).accessibilityIdentifier("explainer.potSlices.call")
          Tag("\(percentText(model.priceNeeded)) needed", style: .plain)
            .accessibilityIdentifier("explainer.potSlices.price")
        }
        Text(model.caption)
          .font(theme.bodyFont(size: 13, weight: .medium))
          .foregroundStyle(theme.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("explainer.potSlices.caption")
      }
    }
    .explainerSurface()
    .explainerContainer("explainer.potSlices", label: model.caption)
  }

  private func pie(progress p: Double) -> some View {
    let split = segment(p, 0, 0.45)
    let fill = segment(p, 0.45, 1)
    let n = model.slices
    return Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = min(size.width, size.height) / 2 - 8
      let step = 2 * Double.pi / Double(n)
      for i in 0..<n {
        let start = -Double.pi / 2 + step * Double(i)
        let mid = start + step / 2
        let gap = 6.0 * split
        let origin = CGPoint(x: center.x + cos(mid) * gap, y: center.y + sin(mid) * gap)
        var slice = Path()
        slice.move(to: origin)
        slice.addArc(
          center: origin, radius: radius, startAngle: .radians(start), endAngle: .radians(start + step),
          clockwise: false)
        slice.closeSubpath()
        let isCall = i == 0
        context.fill(slice, with: .color(theme.gold.opacity(0.55)))
        if isCall {
          var inner = context
          inner.clip(to: slice)
          let r = radius * fill
          inner.fill(
            Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2)),
            with: .color(theme.rune))
        }
        context.stroke(slice, with: .color(theme.ink.opacity(0.75)), lineWidth: 1.5)
        let labelPoint = CGPoint(
          x: origin.x + cos(mid) * radius * 0.62, y: origin.y + sin(mid) * radius * 0.62)
        let label = Text(isCall ? "pay" : "\(i)")
          .font(theme.displayFont(size: isCall ? 11 : 13))
          .foregroundColor(theme.ink)
        if n <= 8 || isCall { context.draw(label, at: labelPoint, anchor: .center) }
      }
    }
  }
}
