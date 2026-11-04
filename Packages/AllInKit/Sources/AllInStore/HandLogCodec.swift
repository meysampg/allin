import Foundation
import PokerCore

public enum HandLogCodecError: Error, Equatable {
  case compressionFailed
}

/// `EventLog` to compact bytes: sorted-key JSON, then LZFSE.
public enum HandLogCodec {
  public static func encode(_ log: EventLog) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try encoder.encode(log)
    do {
      return try (json as NSData).compressed(using: .lzfse) as Data
    } catch {
      throw HandLogCodecError.compressionFailed
    }
  }

  public static func decode(_ data: Data) throws -> EventLog {
    let json = try (data as NSData).decompressed(using: .lzfse) as Data
    return try JSONDecoder().decode(EventLog.self, from: json)
  }
}
