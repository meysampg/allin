import Foundation

public enum AssetSource: Sendable, Hashable {
  case file(URL)
  case procedural(ProceduralID, ProceduralParams)
  case files([URL])
}
