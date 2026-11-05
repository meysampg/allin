import AllInUI
import Curriculum
import PokerCore
import PokerEquity
import SwiftUI

/// How the player answers a spot.
enum LessonInputKind: Equatable {
  case single, multiple, number, cards(limit: Int?), range

  init(_ solution: SpotSolution) {
    switch solution.correct {
    case .option: self = .single
    case .options: self = .multiple
    case .number: self = .number
    case .cards: self = .cards(limit: solution.pick)
    case .range: self = .range
    }
  }
}

extension String {
  /// `bet:0.5` becomes `bet-0-5`.
  var lessonIdentifier: String {
    replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
  }
}

/// The option buttons: one tap answers a single choice; a multiple choice toggles and waits for Submit.
struct LessonOptionButtons: View {
  let options: [AnswerOption]
  let multiple: Bool
  let primaryIndex: Int?
  @Binding var chosen: Set<String>
  let answer: (String) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
          Button {
            if multiple {
              if chosen.contains(option.id) { chosen.remove(option.id) } else { chosen.insert(option.id) }
            } else {
              answer(option.id)
            }
          } label: {
            Text(multiple && chosen.contains(option.id) ? "\u{2713} \(option.label)" : option.label)
          }
          .buttonStyle(.fantasy(index == primaryIndex || chosen.contains(option.id) ? .primary : .secondary))
          .accessibilityIdentifier("lesson.option.\(option.id.lessonIdentifier)")
        }
      }
      .padding(.vertical, 4)
    }
    .scrollBounceBehavior(.basedOnSize)
  }
}

/// A whole-number field with its own Submit button.
struct LessonNumberInput: View {
  @Environment(\.theme) private var theme
  @Binding var text: String
  let submit: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 10) {
      TextField("Type a number", text: $text)
        .textFieldStyle(.roundedBorder)
        .frame(width: 140)
        .focused($focused)
        .onSubmit { if Int(text) != nil { submit() } }
        .onChange(of: text) { _, new in
          let digits = new.filter(\.isNumber)
          if digits != new { text = digits }
        }
        .accessibilityIdentifier("lesson.number")
      Button("Submit", action: submit)
        .buttonStyle(.fantasy(.primary))
        .disabled(Int(text) == nil)
        .accessibilityIdentifier("lesson.submit")
    }
    .onAppear { focused = true }
  }
}

/// A submit button for the inputs that live in a floating panel.
struct LessonSubmitButton: View {
  let enabled: Bool
  let submit: () -> Void

  var body: some View {
    Button("Submit", action: submit)
      .buttonStyle(.fantasy(.primary))
      .disabled(!enabled)
      .accessibilityIdentifier("lesson.submit")
  }
}

/// The card picker above the answer bar.
struct LessonCardsPanel: View {
  @Environment(\.theme) private var theme
  @Binding var cards: [Card]
  let limit: Int?
  let dead: CardSet
  let fourColor: Bool

  var body: some View {
    ParchmentPanel(title: limit.map { "Pick \($0) card\($0 == 1 ? "" : "s")" } ?? "Pick the cards") {
      CardPickerView(selection: $cards, limit: limit, dead: dead, fourColor: fourColor)
        .accessibilityIdentifier("lesson.cardPicker")
    }
    .fixedSize()
  }
}

/// The range painter above the answer bar.
struct LessonRangePanel: View {
  @Binding var weights: [[Float]]

  var body: some View {
    ParchmentPanel(title: "Paint the hands") {
      RangePainterView(weights: $weights, cellSize: 18)
        .accessibilityIdentifier("lesson.rangePainter")
    }
    .fixedSize()
  }
}
