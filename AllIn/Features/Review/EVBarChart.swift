import AllInUI
import Charts
import PokerAnalysis
import SwiftUI

/// Average result of each option in big blinds: the best bar gold, yours outlined, losses in red.
struct EVBarChart: View {
  @Environment(\.theme) private var theme
  let decision: ReviewedDecision

  private struct Bar: Identifiable {
    let id: Int
    let label: String
    let ev: Double
    let isBest: Bool
    let isChosen: Bool
  }

  private var bars: [Bar] {
    let graded = decision.graded
    return graded.candidates.enumerated().map { index, candidate in
      Bar(
        id: index, label: candidate.shortLabel, ev: candidate.evBB, isBest: candidate.action == graded.best.action,
        isChosen: candidate.action == graded.chosen.action)
    }
  }

  var body: some View {
    let bars = bars
    Chart(bars) { bar in
      BarMark(x: .value("Action", String(bar.id)), y: .value("EV (bb)", bar.ev))
        .foregroundStyle(color(bar))
        .cornerRadius(3)
        .annotation(position: bar.ev >= 0 ? .top : .bottom, spacing: 2) {
          Text(Self.format(bar.ev))
            .font(theme.bodyFont(size: 10, weight: bar.isChosen ? .bold : .regular))
            .foregroundStyle(theme.ink)
        }
      if bar.isChosen {
        BarMark(x: .value("Action", String(bar.id)), y: .value("EV (bb)", bar.ev))
          .foregroundStyle(.clear)
          .cornerRadius(3)
          .annotation(position: .overlay) {
            RoundedRectangle(cornerRadius: 3).strokeBorder(theme.ink, lineWidth: 2)
          }
      }
    }
    .chartXAxis {
      AxisMarks { value in
        AxisValueLabel {
          if let raw = value.as(String.self), let index = Int(raw), bars.indices.contains(index) {
            Text(bars[index].label)
              .font(theme.bodyFont(size: 10, weight: bars[index].isChosen ? .bold : .regular))
              .foregroundStyle(theme.ink)
          }
        }
      }
    }
    .chartYAxis(.hidden)
    .chartYScale(domain: yDomain(bars))
    .frame(height: 120)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(summary(bars))
    .accessibilityIdentifier("review.evChart")
  }

  private func color(_ bar: Bar) -> Color {
    if bar.isBest { return theme.gold }
    return bar.ev < 0 ? theme.bad : theme.ink.opacity(0.45)
  }

  private func yDomain(_ bars: [Bar]) -> ClosedRange<Double> {
    let low = min(0, bars.map(\.ev).min() ?? 0)
    let high = max(0, bars.map(\.ev).max() ?? 0)
    let pad = max(1, (high - low) * 0.22)
    return (low < 0 ? low - pad : 0)...(high + pad)
  }

  private func summary(_ bars: [Bar]) -> String {
    bars.map { "\($0.label) \(Self.format($0.ev)) bb" }.joined(separator: ", ")
  }

  static func format(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    let text = String(format: "%.1f", abs(rounded))
    return rounded < 0 ? "\u{2212}\(text)" : (rounded > 0 ? "+\(text)" : text)
  }
}
