import Foundation

public enum NeoError: Error, CustomStringConvertible {
    case deviceNotFound
    case flipFailed
    case usb(String, Error?)
    case timeout
    case protocolError(String)
    case unexpectedResponse(expected: UInt8, got: Message)
    case checksumMismatch(expected: Int, got: Int)

    public var description: String {
        switch self {
        case .deviceNotFound: return "AlphaSmart Neo not found"
        case .flipFailed: return "The Neo didn't switch into transfer mode"
        case let .usb(what, err): return "USB \(what) failed" + (err.map { ": \($0.localizedDescription)" } ?? "")
        case .timeout: return "Timed out waiting for the Neo"
        case let .protocolError(s): return s
        case let .unexpectedResponse(expected, got):
            return "Expected response 0x\(String(expected, radix: 16)), got \(got) (\(Response.errorText(got.command)))"
        case let .checksumMismatch(expected, got): return "Checksum mismatch (expected \(expected), got \(got))"
        }
    }
}

/// Raw byte pipe to the Neo in comms mode.
public protocol NeoTransport: AnyObject {
    /// Writes `bytes` in 8-byte packets.
    func write(_ bytes: [UInt8], timeout: TimeInterval) throws
    /// Reads up to `count` bytes in 8-byte packets, stopping early on a short packet.
    func read(_ count: Int, timeout: TimeInterval) throws -> [UInt8]
}

public enum USBIDs {
    public static let vendor = 0x081E
    public static let keyboardProduct = 0xBD04
    public static let commsProduct = 0xBD01
}
