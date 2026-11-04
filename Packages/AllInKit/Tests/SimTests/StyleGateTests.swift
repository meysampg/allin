import PokerAI
import PokerCore
import PokerHost
import Testing

@Suite struct SimStyleGateTests {
  private static let bands: [String: ClosedRange<Double>] = ["grumli": 0.50...0.60, "vexa": 0.12...0.16]

  /// 6-max ring: the personality at seat 0 and five Oryn, 10,000 hands. Only Grumli and Vexa VPIP are gated.
  @Test(arguments: SimSupport.gateIDs)
  func sixMaxStyle(id: String) async {
    let oryn = SimSupport.contestant("oryn")
    let players = [SimSupport.contestant(id)] + Array(repeating: oryn, count: 5)
    let (report, seconds) = await SimSupport.timed {
      HeadlessMatch.ring(players, config: .sixMax(hands: 10_000, seed: SimSupport.styleSeed))
    }
    let style = report.styles[0]
    let band = Self.bands[id].map { "band \($0.lowerBound)-\($0.upperBound)" } ?? "ungated"
    let speed = String(format: "%.0f", Double(report.hands) / max(seconds, 0.001))
    print(
      "SIM style \(id): VPIP \(String(format: "%.3f", style.vpip)) PFR \(String(format: "%.3f", style.pfr)) "
        + "\(band), \(speed) hands/s")
    if let range = Self.bands[id] { #expect(range.contains(style.vpip)) }
  }
}
