import SwiftUI

/// A running total of everything in the middle.
public struct PotCounterModel: Sendable, Hashable {
  public struct Entry: Sendable, Hashable {
    public var label: String
    public var amount: Int

    public init(label: String, amount: Int) {
      self.label = label
      self.amount = amount
    }
  }

  public var entries: [Entry]
  public var total: Int
  public var toCall: Int?

  /// `total` defaults to the sum of the entries.
  public init(entries: [Entry], total: Int? = nil, toCall: Int? = nil) {
    self.entries = entries
    self.total = total ?? entries.reduce(0) { $0 + $1.amount }
    self.toCall = toCall
  }

  /// Total after each entry.
  public var runningTotals: [Int] {
    var sum = 0
    return entries.map {
      sum += $0.amount
      return sum
    }
  }
}

public struct PotCounterView: View {
  @Environment(\.theme) private var theme
  private let model: PotCounterModel

  public init(model: PotCounterModel) { self.model = model }

  public var body: some View {
    Reveal { p in
      let count = max(1, model.entries.count)
      let totals = model.runningTotals
      VStack(spacing: 4) {
        ForEach(Array(model.entries.enumerated()), id: \.offset) { index, entry in
          let from = 0.7 * Double(index) / Double(count)
          let shown = segment(p, from, from + 0.2)
          HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.fill").foregroundStyle(theme.gold)
              .font(.system(size: 11))
            Text(entry.label).font(theme.bodyFont(size: 13, weight: .medium)).foregroundStyle(theme.ink)
            Spacer(minLength: 12)
            Text("+\(entry.amount)").font(theme.bodyFont(size: 13, weight: .bold)).foregroundStyle(theme.ink)
              .accessibilityIdentifier("explainer.potCounter.entry.\(index)")
            Text("\(totals[index])").font(theme.bodyFont(size: 11)).foregroundStyle(theme.mute)
              .frame(width: 36, alignment: .trailing)
          }
          .opacity(shown)
          .offset(y: 8 * (1 - shown))
        }
        Rectangle().fill(theme.ink.opacity(0.5)).frame(height: 1.5)
        HStack {
          Text("POT").font(theme.displayFont(size: 14)).foregroundStyle(theme.ink)
          Spacer()
          Text("\(Int((Double(model.total) * segment(p, 0.1, 0.95)).rounded()))")
            .font(theme.displayFont(size: 24))
            .foregroundStyle(theme.ink)
            .monospacedDigit()
            .accessibilityLabel("Pot \(model.total)")
            .accessibilityIdentifier("explainer.potCounter.total")
        }
        if let toCall = model.toCall {
          HStack {
            Tag("To call \(toCall)", style: .dark).accessibilityIdentifier("explainer.potCounter.toCall")
            Spacer()
          }
          .opacity(segment(p, 0.8, 1))
        }
      }
    }
    .frame(maxWidth: 320)
    .explainerSurface()
    .explainerContainer("explainer.potCounter", label: accessibilityText)
  }

  private var accessibilityText: String {
    "Pot \(model.total)" + (model.toCall.map { ", \($0) to call" } ?? "")
  }
}
