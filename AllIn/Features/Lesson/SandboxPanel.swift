import AllInUI
import Curriculum
import PokerCore
import PokerEquity
import SwiftUI

/// The right half of screen 5, "Alchemist's Bench": editable cards, a bet slider and live bars.
struct SandboxPanel: View {
  @Environment(\.theme) private var theme
  @Environment(AppModel.self) private var app: AppModel?
  let setup: SandboxSetup
  let nextLabel: String
  let onNext: @MainActor () -> Void
  @State private var controller: SandboxController
  @State private var pickerSlot: SandboxSlot?

  init(setup: SandboxSetup, nextLabel: String, onNext: @escaping @MainActor () -> Void) {
    self.setup = setup
    self.nextLabel = nextLabel
    self.onNext = onNext
    self._controller = State(initialValue: SandboxController(setup: setup))
  }

  private var fourColor: Bool { app?.settings.fourColorDeck ?? false }
  private let labelWidth: CGFloat = 118

  var body: some View {
    ParchmentPanel(padding: 16) {
      VStack(alignment: .leading, spacing: 0) {
        Text("\u{1F9EA} \(setup.title)")
          .font(theme.displayFont(size: 17))
          .foregroundStyle(theme.ink)
          .accessibilityIdentifier("sandbox.title")
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            heroRow
            boardRow
            betRow
            metersSection
            liveExplainer
            if let challenge = setup.challenge, !challenge.isEmpty { challengeBox(challenge) }
          }
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        HStack {
          Spacer()
          ExplainNextButton(label: nextLabel, action: onNext)
        }
        .padding(.top, 6)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sandbox.panel")
    .onAppear { controller.start() }
    .onDisappear { controller.stop() }
  }

  // MARK: Cards

  private var cardSize: CardViewSize { .width(40) }

  private var heroRow: some View {
    HStack(spacing: 10) {
      rowLabel("Your cards")
      HStack(spacing: 6) {
        ForEach(0..<max(2, controller.state.heroCards.count), id: \.self) { i in
          slot(.hero(i), card: controller.state.heroCards.indices.contains(i) ? controller.state.heroCards[i] : nil)
            .accessibilityIdentifier("sandbox.heroCard.\(i)")
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("sandbox.heroCards")
      if setup.controls.contains(.heroCards) {
        Tag("drag to change", style: .plain).accessibilityIdentifier("sandbox.dragHint")
      }
      Spacer(minLength: 0)
    }
  }

  private var boardRow: some View {
    HStack(spacing: 10) {
      rowLabel("Board")
      HStack(spacing: 6) {
        ForEach(0..<5, id: \.self) { i in
          Group {
            if controller.state.board.indices.contains(i) {
              slot(.board(i), card: controller.state.board[i])
            } else {
              CardView(card: nil, size: cardSize, fourColor: fourColor)
            }
          }
          .accessibilityIdentifier("sandbox.boardCard.\(i)")
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("sandbox.board")
      Spacer(minLength: 0)
    }
  }

  private func editable(_ slot: SandboxSlot) -> Bool {
    switch slot {
    case .hero: setup.controls.contains(.heroCards)
    case .board: setup.controls.contains(.board)
    }
  }

  @ViewBuilder
  private func slot(_ slot: SandboxSlot, card: Card?) -> some View {
    if let card, editable(slot) {
      Button {
        pickerSlot = slot
      } label: {
        CardView(card: card, size: cardSize, fourColor: fourColor)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Choose a different card")
      .draggable(card.description) { CardView(card: card, size: cardSize, fourColor: fourColor) }
      .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
        return accept(items, on: slot)
      }
      .popover(isPresented: pickerBinding(slot), arrowEdge: .bottom) { picker(for: slot, current: card) }
    } else {
      CardView(card: card, size: cardSize, fourColor: fourColor)
    }
  }

  private func pickerBinding(_ slot: SandboxSlot) -> Binding<Bool> {
    Binding(
      get: { pickerSlot == slot },
      set: { if !$0, pickerSlot == slot { pickerSlot = nil } })
  }

  private func picker(for slot: SandboxSlot, current: Card) -> some View {
    let selection = Binding<[Card]>(
      get: { [current] },
      set: { picked in
        guard let card = picked.last, card != current else { return }
        controller.setCard(slot, to: card)
        pickerSlot = nil
      })
    return CardPickerView(
      selection: selection, limit: 1, dead: controller.dead(excluding: slot), fourColor: fourColor
    )
    .padding(8)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sandbox.cardPicker")
  }

  private func accept(_ items: [String], on slot: SandboxSlot) -> Bool {
    guard let text = items.first, let card = (try? Card.parseList(text))?.first else { return false }
    controller.setCard(slot, to: card)
    return true
  }

  // MARK: Bet

  private var betRow: some View {
    let state = controller.state
    let range = state.betRange
    return HStack(spacing: 10) {
      rowLabel("\(state.villainName)'s bet")
        .accessibilityIdentifier("sandbox.bet.label")
      if setup.controls.contains(.villainBet), range.lowerBound < range.upperBound {
        Slider(
          value: Binding(get: { Double(controller.state.villainBet) }, set: { controller.setBet(Int($0.rounded())) }),
          in: Double(range.lowerBound)...Double(range.upperBound), step: Double(controller.betStep)
        )
        .tint(theme.gold)
        .background(
          Capsule().fill(theme.ink.opacity(0.22)).frame(height: 6)
            .overlay(Capsule().strokeBorder(theme.ink.opacity(0.5), lineWidth: 1).frame(height: 6))
        )
        .accessibilityLabel("\(state.villainName)'s bet")
        .accessibilityIdentifier("sandbox.bet")
      } else {
        Spacer(minLength: 0)
      }
      Text("\(state.villainBet)")
        .font(theme.bodyFont(size: 16, weight: .bold))
        .foregroundStyle(theme.ink)
        .monospacedDigit()
        .frame(width: 52, alignment: .trailing)
        .accessibilityIdentifier("sandbox.bet.value")
    }
  }

  // MARK: Meters

  @ViewBuilder
  private var metersSection: some View {
    let meters = setup.meters
    let readings = controller.readings
    VStack(alignment: .leading, spacing: 10) {
      if meters.contains(.priceNeeded) && meters.contains(.yourChance) {
        EquityBars(
          model: EquityBarsModel(
            priceNeeded: readings.priceNeeded, chance: controller.chance, isRefining: controller.isRefining)
        )
        .accessibilityElement(children: .contain)
        priceLine(readings)
      } else if meters.contains(.priceNeeded) {
        EquityBars(model: EquityBarsModel(priceNeeded: readings.priceNeeded, chance: nil))
        priceLine(readings)
      } else if meters.contains(.yourChance) {
        let model = EquityBarsModel(priceNeeded: nil, chance: controller.chance, isRefining: controller.isRefining)
        EquityBars(model: model)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("sandbox.meter.yourChance")
      }
      ForEach(meters.filter { ![.priceNeeded, .yourChance].contains($0) }, id: \.self) { meter in
        meterRow(meter, readings)
      }
    }
  }

  /// "Call 50 to win 150: break-even at 25%" with a verdict tag once the chance is in.
  private func priceLine(_ r: SandboxReadings) -> some View {
    let state = controller.state
    let percent = r.priceNeeded.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    let win = state.potBeforeBet + state.villainBet
    return HStack(spacing: 8) {
      Text("Call \(state.villainBet) to win \(win): break-even at \(percent).")
        .font(theme.bodyFont(size: 12, weight: .medium))
        .foregroundStyle(theme.mute)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Price you need")
        .accessibilityValue(percent)
        .accessibilityIdentifier("sandbox.meter.priceNeeded")
      Spacer(minLength: 0)
      if let price = r.priceNeeded, let chance = controller.chance, !controller.isRefining {
        Tag(chance > price ? "Calling pays" : "Folding is better", style: chance > price ? .good : .bad)
          .accessibilityIdentifier("sandbox.verdict")
      }
    }
  }

  @ViewBuilder
  private func meterRow(_ meter: SandboxMeter, _ r: SandboxReadings) -> some View {
    switch meter {
    case .potAfter:
      textRow("Pot after call", r.potAfterCall.map(String.init) ?? "–", id: meter)
    case .outs:
      let outs = r.outs ?? []
      HStack(alignment: .center, spacing: 10) {
        rowLabel("Outs")
        Text("\(outs.count)")
          .font(theme.bodyFont(size: 14, weight: .bold))
          .foregroundStyle(theme.ink)
          .accessibilityIdentifier("sandbox.meter.outs")
        miniCards(outs)
      }
    case .bestFive:
      VStack(alignment: .leading, spacing: 6) {
        textRow("Best five", r.bestFiveText ?? "–", id: meter)
        miniCards(r.bestFive ?? [])
      }
    case .nuts:
      textRow("Best possible", r.nutsText ?? "–", id: meter)
    case .worseThatCall:
      shareRow("Worse hands that call", r.worseInRange, tint: theme.good, id: meter)
    case .betterThatCall:
      shareRow("Better hands that call", r.betterInRange, tint: theme.bad, id: meter)
    case .priceNeeded, .yourChance:
      EmptyView()
    }
  }

  private func textRow(_ label: String, _ value: String, id: SandboxMeter) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      rowLabel(label)
      Text(value)
        .font(theme.bodyFont(size: 14, weight: .bold))
        .foregroundStyle(theme.ink)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("sandbox.meter.\(id.rawValue)")
      Spacer(minLength: 0)
    }
  }

  private func shareRow(_ label: String, _ share: Double?, tint: Color, id: SandboxMeter) -> some View {
    HStack(spacing: 10) {
      Text(label)
        .font(theme.bodyFont(size: 13, weight: .semibold))
        .foregroundStyle(theme.ink)
        .frame(width: 150, alignment: .leading)
      Meter(value: share ?? 0, tint: tint)
      Text(share.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
        .font(theme.bodyFont(size: 14, weight: .bold))
        .foregroundStyle(theme.ink)
        .monospacedDigit()
        .frame(width: 44, alignment: .trailing)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(share.map { "\(Int(($0 * 100).rounded()))%" } ?? "unknown")
    .accessibilityIdentifier("sandbox.meter.\(id.rawValue)")
  }

  private func miniCards(_ cards: [Card]) -> some View {
    HStack(spacing: 3) {
      ForEach(Array(cards.prefix(16).enumerated()), id: \.offset) { _, card in
        CardView(card: card, size: .width(24), fourColor: fourColor)
      }
    }
  }

  // MARK: Live explainer

  @ViewBuilder
  private var liveExplainer: some View {
    let s = controller.state
    let r = controller.readings
    switch setup.explainer {
    case .potSlices:
      PotSlicesView(model: PotSlicesModel(pot: s.potBeforeBet + s.villainBet, call: s.villainBet))
    case .outsGlow where s.heroCards.count == 2 && (3...4).contains(s.board.count):
      let outs = r.outs ?? BoardAnalyzer.outs(hole: s.heroCards, board: s.board)
      OutsGlowView(
        model: OutsGlowModel(
          hole: s.heroCards, board: s.board, outs: outs, unseen: 52 - s.heroCards.count - s.board.count))
    case .bestFiveHighlight where s.heroCards.count == 2 && s.board.count >= 3:
      if let best = r.bestFive {
        BestFiveHighlightView(
          model: BestFiveModel(cards: s.heroCards + s.board, best: best, description: r.bestFiveText ?? ""))
      }
    default:
      EmptyView()
    }
  }

  // MARK: Pieces

  private func rowLabel(_ text: String) -> some View {
    Text(text)
      .font(theme.bodyFont(size: 13, weight: .semibold))
      .foregroundStyle(theme.mute)
      .frame(width: labelWidth, alignment: .leading)
  }

  private func challengeBox(_ text: String) -> some View {
    Text(text)
      .font(theme.bodyFont(size: 13, weight: .medium))
      .foregroundStyle(theme.ink)
      .lineSpacing(2)
      .fixedSize(horizontal: false, vertical: true)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.gold.opacity(0.22)))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(theme.gold.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
      )
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("sandbox.challenge")
  }
}
