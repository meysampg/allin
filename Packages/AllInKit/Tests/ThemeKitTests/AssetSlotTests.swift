import Testing

@testable import ThemeKit

@Suite struct AssetSlotTests {
  @Test func catalogIDsRoundTrip() {
    for slot in AssetSlot.catalog() {
      #expect(AssetSlot(id: slot.id) == slot, "\(slot.id)")
    }
  }

  @Test func catalogHasNoDuplicatesAndExpectedCounts() {
    let slots = AssetSlot.catalog()
    #expect(Set(slots.map(\.id)).count == slots.count)
    #expect(slots.count > 52 + 12)
    let courts = slots.filter { if case .cardCourt = $0 { true } else { false } }
    #expect(courts.count == 12)
  }

  @Test func parsesKnownIDs() {
    #expect(AssetSlot(id: "card.face.As") == .cardFaceOverride(CardKey(symbol: "As")!))
    #expect(AssetSlot(id: "chip.1k") == .chip(.thousand))
    #expect(AssetSlot(id: "sound.card.deal") == .sound(.cardDeal))
    #expect(AssetSlot(id: "character.grumli.full") == .characterFull("grumli"))
    #expect(AssetSlot(id: "venue.tavern.map") == .venueMap("tavern"))
  }

  @Test func rejectsBadIDs() {
    for id in ["card.face.Zz", "chip.7", "bogus", "", "card.court.2c", "card.court.Th", "avatar.Bad", "venue.x.nope"] {
      #expect(AssetSlot(id: id) == nil, "\(id)")
    }
  }

  @Test func kindsAndFallbacks() {
    #expect(AssetSlot.sound(.win).kind == .sound)
    #expect(AssetSlot.music("tavern").kind == .music)
    #expect(AssetSlot.fontBody.kind == .font)
    #expect(AssetSlot.fx(.embers).kind == .effect)
    #expect(AssetSlot.chip(.five).kind == .image)
    #expect(AssetSlot.cardBackReward("x").fallbackSlot == .cardBack)
    #expect(AssetSlot.cardFaceOverride(CardKey(symbol: "2c")!).fallbackSlot == .cardFace)
    #expect(AssetSlot.tableFelt.fallbackSlot == nil)
  }

  @Test func cardKeys() {
    #expect(CardKey.all.count == 52)
    #expect(CardKey.all[0].symbol == "2c")
    #expect(CardKey.all[51].symbol == "As")
    #expect(CardKey(rank: 13, suit: 0) == nil)
    #expect(CardKey(symbol: "Th")?.rank == 8)
  }
}
