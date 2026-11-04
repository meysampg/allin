import Foundation
import Testing

@testable import PokerAI

@Suite struct CharacterFileTests {
  private let directory = BotCharacter.sourceTreeDirectory

  @Test func everyFileDecodesAndValidates() throws {
    let characters = try BotCharacter.loadAll(directory: directory)
    #expect(characters.count == 7)
    #expect(Set(characters.map(\.id)).count == characters.count)
    #expect(characters.map(\.id) == characters.map(\.id).sorted())
    for character in characters {
      try character.validate()
      #expect(character.schemaVersion == 1)
    }
  }

  @Test func fileNameEqualsId() throws {
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
    #expect(files.count == 7)
    for file in files {
      let character = try BotCharacter.load(from: file)
      #expect(file.deletingPathExtension().lastPathComponent == character.id)
    }
  }

  @Test func strategyKinds() throws {
    let characters = try BotCharacter.loadAll(directory: directory)
    for character in characters {
      if character.id == "oryn" {
        #expect(character.strategy == .baseline)
        #expect(character.params == nil)
      } else {
        #expect(character.strategy == .personality)
        #expect(character.params != nil)
      }
    }
    let patron = try #require(characters.first { $0.id == "patron" })
    #expect(patron.variation?["vpip"] == 0.10)
  }

  @Test func startingValuesMatchThePlan() throws {
    let grumli = try #require(try BotCharacter.loadAll(directory: directory).first { $0.id == "grumli" }?.params)
    #expect(grumli.vpip == 0.55)
    #expect(grumli.stickiness == 0.90)
    #expect(grumli.sizing.openRaiseBB == 2.5)
  }

  @Test func rejectsBadCharacters() throws {
    let params = try #require(try BotCharacter.loadAll(directory: directory).first { $0.id == "grumli" }?.params)
    #expect(throws: BotCharacterError.self) {
      try BotCharacter(id: "x", name: "X", style: "s", strategy: .personality).validate()
    }
    #expect(throws: BotCharacterError.self) {
      try BotCharacter(id: "x", name: "X", style: "s", strategy: .personality, params: params, variation: ["nope": 0.1])
        .validate()
    }
    var broken = params
    broken.vpip = 1.5
    #expect(throws: BotCharacterError.self) {
      try BotCharacter(id: "x", name: "X", style: "s", strategy: .personality, params: broken).validate()
    }
    #expect(throws: BotCharacterError.self) {
      try BotCharacter(schemaVersion: 2, id: "x", name: "X", style: "s", strategy: .baseline).validate()
    }
  }

  @Test func codableRoundTrip() throws {
    for character in try BotCharacter.loadAll(directory: directory) {
      let data = try JSONEncoder().encode(character)
      #expect(try JSONDecoder().decode(BotCharacter.self, from: data) == character)
    }
  }
}
