import Testing

@testable import PokerCore

@Suite struct EventsSHA256Tests {
  @Test func nistVectors() {
    #expect(SHA256.hex([]) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA256.hex(Array("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    let long = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    #expect(SHA256.hex(Array(long.utf8)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  }

  @Test func millionAs() {
    let input = [UInt8](repeating: 0x61, count: 1_000_000)
    #expect(SHA256.hex(input) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
  }

  @Test func paddingBoundaries() {
    // 55, 56 and 64 bytes straddle the one-block / two-block padding edge.
    #expect(
      SHA256.hex([UInt8](repeating: 0x61, count: 55))
        == "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318")
    #expect(
      SHA256.hex([UInt8](repeating: 0x61, count: 56))
        == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a")
    #expect(
      SHA256.hex([UInt8](repeating: 0x61, count: 64))
        == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")
  }

  @Test func deckCommitmentMatchesPreviousImplementation() {
    let expected: [UInt64: String] = [
      1: "e77aad28527976954fd971356aaadc94c6702636f811c9ac938e6e9fea48d37d",
      42: "b22032a57a7b032158ecacd5382298300a0c7ef5521179e69b4fcc70ee2eade6",
      20_240_607: "10eb5b24b739e9d5915e18d602c18db7260af0dc1f54278a5a949ddb3d379467",
    ]
    for (seed, hex) in expected {
      var deck = Deck()
      var rng = SeededRNG(seed: seed)
      deck.shuffle(using: &rng)
      #expect(HandStart.commitment(for: Array(deck.undealt)) == hex)
    }
    #expect(HandStart.commitment(for: Card.all) == "c4c6540a15fc140a784056fe6d9e13566fb614ecb2d9ac0331e264c386442acd")
  }
}
