import PokerCore

/// When busted or short seats get more chips.
public enum TopUpPolicy: Sendable, Hashable {
  /// Busted seats sit out.
  case none
  /// Before each hand: stack < threshold → top up to the buy-in.
  case refillBelow(Int)
  /// Stack == 0 → top up to the buy-in.
  case rebuyWhenBusted
}

/// Static setup of a cash session.
public struct CashSessionConfig: Sendable, Hashable {
  public var table: TableConfig
  public var buyIn: Int
  public var topUp: TopUpPolicy
  public var seed: UInt64
  /// nil → lowest occupied seat.
  public var firstButton: Int?
  public var firstHandID: UInt64
  public var hostOptions: HostOptions

  public init(
    table: TableConfig, buyIn: Int, topUp: TopUpPolicy = .none, seed: UInt64,
    firstButton: Int? = nil, firstHandID: UInt64 = 1, hostOptions: HostOptions = HostOptions()
  ) {
    self.table = table
    self.buyIn = buyIn
    self.topUp = topUp
    self.seed = seed
    self.firstButton = firstButton
    self.firstHandID = firstHandID
    self.hostOptions = hostOptions
  }
}
