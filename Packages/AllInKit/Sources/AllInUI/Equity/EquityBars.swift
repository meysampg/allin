import SwiftUI

/// Price you need versus your chance, as two live bars.
public struct EquityBarsModel: Sendable, Hashable {
  public var priceNeeded: Double?
  public var chance: Double?
  /// True while a better estimate is still being computed.
  public var isRefining: Bool
  public var priceLabel: String
  public var chanceLabel: String

  public init(
    priceNeeded: Double?, chance: Double?, isRefining: Bool = false, priceLabel: String = "Price you need",
    chanceLabel: String = "Your chance"
  ) {
    self.priceNeeded = priceNeeded
    self.chance = chance
    self.isRefining = isRefining
    self.priceLabel = priceLabel
    self.chanceLabel = chanceLabel
  }

  static func clamp(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return min(max(value, 0), 1)
  }

  /// `priceNeeded` clamped to 0...1.
  public var priceFraction: Double? { Self.clamp(priceNeeded) }
  /// `chance` clamped to 0...1.
  public var chanceFraction: Double? { Self.clamp(chance) }
  public var priceText: String { priceFraction.map(percentText) ?? "–" }
  public var chanceText: String { chanceFraction.map(percentText) ?? "–" }

  /// True when the hand wins often enough to pay the price.
  public var isProfitable: Bool? {
    guard let price = priceFraction, let chance = chanceFraction else { return nil }
    return chance > price
  }
}

public struct EquityBars: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.explainerAnimates) private var animates
  private let model: EquityBarsModel

  public init(model: EquityBarsModel) { self.model = model }

  public var body: some View {
    VStack(spacing: 8) {
      bar(
        id: "equityBars.price", label: model.priceLabel, fraction: model.priceFraction, text: model.priceText,
        tint: AnyShapeStyle(
          LinearGradient(colors: [theme.gold.opacity(0.8), theme.gold], startPoint: .leading, endPoint: .trailing)),
        refining: false)
      bar(
        id: "equityBars.chance", label: model.chanceLabel, fraction: model.chanceFraction, text: model.chanceText,
        tint: AnyShapeStyle(chanceTint), refining: model.isRefining)
    }
  }

  private var chanceTint: LinearGradient {
    let base = model.isProfitable == false ? theme.bad : theme.good
    return LinearGradient(colors: [base.opacity(0.8), base], startPoint: .leading, endPoint: .trailing)
  }

  private func bar(id: String, label: String, fraction: Double?, text: String, tint: AnyShapeStyle, refining: Bool)
    -> some View
  {
    HStack(spacing: 10) {
      Text(label)
        .font(theme.bodyFont(size: 13, weight: .semibold))
        .foregroundStyle(theme.ink)
        .frame(width: 118, alignment: .leading)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(theme.ink.opacity(0.16))
          Capsule().fill(tint)
            .frame(width: max(fraction.map { $0 > 0 ? 8 : 0 } ?? 0, proxy.size.width * (fraction ?? 0)))
            .opacity(refining ? 0.8 : 1)
          if refining { shimmer(width: proxy.size.width) }
        }
        .overlay(Capsule().strokeBorder(theme.ink.opacity(0.6), lineWidth: 1))
      }
      .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)
      .animation(reduceMotion || !animates ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: fraction)
      Text(text)
        .font(theme.bodyFont(size: 14, weight: .bold))
        .foregroundStyle(theme.ink)
        .monospacedDigit()
        .frame(width: 44, alignment: .trailing)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label + (refining ? ", refining" : ""))
    .accessibilityValue(text)
    .accessibilityIdentifier(id)
  }

  @ViewBuilder
  private func shimmer(width: CGFloat) -> some View {
    if reduceMotion || !animates {
      EmptyView()
    } else {
      TimelineView(.animation) { timeline in
        let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
        Capsule()
          .fill(
            LinearGradient(
              colors: [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)], startPoint: .leading,
              endPoint: .trailing)
          )
          .frame(width: 44)
          .offset(x: (width + 44) * t - 44)
          .clipShape(Capsule())
      }
      .allowsHitTesting(false)
    }
  }
}
