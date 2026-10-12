import Foundation

/// An 8-byte ASM command or response: a command byte, six argument bytes, and a
/// checksum byte (the low byte of the sum of the first seven).
/// Ported from neotools `message.py`.
public struct Message: Equatable, CustomStringConvertible {
    public private(set) var bytes: [UInt8]

    public init(_ command: UInt8, _ args: [(value: Int, offset: Int, width: Int)] = []) {
        bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = command
        for arg in args {
            Message.validate(offset: arg.offset, width: arg.width)
            var value = arg.value
            for i in stride(from: arg.width - 1, through: 0, by: -1) {
                bytes[arg.offset + i] = UInt8(value & 0xFF)
                value >>= 8
            }
        }
        bytes[7] = checksum
    }

    public init(raw: [UInt8]) {
        bytes = raw
    }

    public var command: UInt8 { bytes.first ?? 0 }

    /// Big-endian unsigned argument of `width` bytes starting at `offset`.
    public func argument(_ offset: Int, _ width: Int) -> Int {
        Message.validate(offset: offset, width: width)
        guard bytes.count >= offset + width else { return 0 }
        return bytes[offset..<offset + width].reduce(0) { $0 << 8 | Int($1) }
    }

    var checksum: UInt8 {
        UInt8(bytes.prefix(7).reduce(0) { $0 + Int($1) } & 0xFF)
    }

    private static func validate(offset: Int, width: Int) {
        precondition((1...4).contains(width), "Invalid width")
        precondition(offset >= 1 && offset + width <= 7, "Invalid offset")
    }

    public var description: String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

enum Command {
    static let version: UInt8 = 0x00
    static let blockWrite: UInt8 = 0x02
    static let restart: UInt8 = 0x08
    static let blockRead: UInt8 = 0x10
    static let getFileAttributes: UInt8 = 0x13
    static let confirmWriteFile: UInt8 = 0x15
    static let getAvailableSpace: UInt8 = 0x1A
    static let readRawFile: UInt8 = 0x1C
    static let setFileAttributes: UInt8 = 0x1D
    static let commit: UInt8 = 0x1E
    static let writeRawFile: UInt8 = 0x1F
}

enum Response {
    static let version: UInt8 = 0x40
    static let blockWrite: UInt8 = 0x42
    static let blockWriteDone: UInt8 = 0x43
    static let blockRead: UInt8 = 0x4D
    static let blockReadEmpty: UInt8 = 0x4E
    static let writeFile: UInt8 = 0x50
    static let confirmWriteFile: UInt8 = 0x51
    static let restart: UInt8 = 0x52
    static let getAvailableSpace: UInt8 = 0x58
    static let getFileAttributes: UInt8 = 0x5A
    static let setFileAttributes: UInt8 = 0x5B
    static let commit: UInt8 = 0x5C

    static let errorParameter: UInt8 = 0x90

    static func errorText(_ code: UInt8) -> String {
        switch code {
        case 0x86: return "Bad baud rate"
        case 0x8A: return "Specified applet ID is not recognised"
        case 0x8F: return "Protocol error"
        case 0x90: return "Parameter error"
        case 0x91: return "Out of memory"
        default: return "Unknown error"
        }
    }
}

public enum AppletID {
    public static let system = 0x0000
    public static let alphaWord = 0xA000
}

/// Sum of all bytes, truncated to 16 bits.
func dataChecksum<S: Sequence>(_ bytes: S) -> Int where S.Element == UInt8 {
    bytes.reduce(0) { ($0 + Int($1)) & 0xFFFF }
}
