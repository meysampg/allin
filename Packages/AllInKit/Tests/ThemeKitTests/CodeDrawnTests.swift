import Testing

@testable import ThemeKit

@Suite struct CodeDrawnTests {
  @Test func everyCatalogSlotIsProceduralWithMatchingKind() {
    for slot in AssetSlot.catalog() {
      guard case .procedural(let id, _) = CodeDrawn.default(slot) else {
        Issue.record("\(slot.id) is not procedural")
        continue
      }
      #expect(id.kind == slot.kind, "\(slot.id) -> \(id.rawValue)")
    }
  }

  @Test func avatarsCarrySymbolRingInitial() {
    for id in CodeDrawn.knownCharacterIDs {
      guard case .procedural(let pid, let params) = CodeDrawn.default(.avatar(id)) else {
        Issue.record("\(id) not procedural")
        continue
      }
      #expect(pid == .medallionSigil)
      #expect(params.values["symbol"] != nil)
      #expect(params.values["ring"] != nil)
      #expect(params.string("initial", default: "") == String(id.prefix(1)).uppercased())
    }
    guard case .procedural(_, let unknown) = CodeDrawn.default(.avatar("zzz")) else { return }
    #expect(unknown.string("symbol", default: "") == "questionmark")
  }

  @Test func rewardBackHueIsStable() {
    #expect(CodeDrawn.default(.cardBackReward("sample")) == CodeDrawn.default(.cardBackReward("sample")))
    #expect(CodeDrawn.default(.cardBackReward("a")) != CodeDrawn.default(.cardBackReward("b")))
  }

  @Test func soundMapping() {
    #expect(CodeDrawn.default(.sound(.uiFail)) == .procedural(.sfxTone, ["from": 440, "to": 220]))
    #expect(CodeDrawn.default(.sound(.allIn)) == .procedural(.sfxBell, ["notes": 1, "base": 220]))
    #expect(CodeDrawn.default(.chip(.fiveThousand)) == .procedural(.gemDiamond, [:]))
  }
}
