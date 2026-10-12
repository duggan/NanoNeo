import Foundation

/// AlphaWord file attributes (40 bytes on the wire). Ported from neotools `file.py`.
public struct FileAttributes: Equatable {
    public var index: Int
    public var name: String
    /// File space: 1–8 for AlphaWord slots, 0 if unbound.
    public var space: Int
    public var password: String
    public var minSize: Int
    public var allocSize: Int
    public var flags: Int

    static let size = 40
    /// Space codes as stored on the device, indexed by space number.
    static let spaceCodes: [UInt8] = [0xFF, 0x2D, 0x2C, 0x04, 0x0F, 0x0E, 0x0A, 0x01, 0x27]

    init(index: Int, raw: [UInt8]) throws {
        guard raw.count == Self.size else {
            throw NeoError.protocolError("File attributes were \(raw.count) bytes, expected \(Self.size)")
        }
        guard let space = Self.spaceCodes.firstIndex(of: raw[0x25]) else {
            throw NeoError.protocolError("Unknown file space code 0x\(String(raw[0x25], radix: 16))")
        }
        self.index = index
        self.name = Self.string(raw, 0x00, 15)
        self.password = Self.string(raw, 0x10, 7)
        self.minSize = Self.int(raw, 0x18, 4)
        self.allocSize = Self.int(raw, 0x1C, 4)
        self.flags = Self.int(raw, 0x20, 4)
        self.space = space
    }

    var raw: [UInt8] {
        var buf = [UInt8](repeating: 0, count: Self.size)
        Self.put(&buf, 0x00, 15, name)
        Self.put(&buf, 0x10, 7, password)
        Self.put(&buf, 0x18, 4, minSize)
        Self.put(&buf, 0x1C, 4, allocSize)
        Self.put(&buf, 0x20, 4, flags)
        buf[0x25] = Self.spaceCodes[space]
        return buf
    }

    private static func string(_ buf: [UInt8], _ offset: Int, _ width: Int) -> String {
        let field = buf[offset..<offset + width]
        let bytes = field.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func int(_ buf: [UInt8], _ offset: Int, _ width: Int) -> Int {
        buf[offset..<offset + width].reduce(0) { $0 << 8 | Int($1) }
    }

    private static func put(_ buf: inout [UInt8], _ offset: Int, _ width: Int, _ value: String) {
        for (i, b) in value.utf8.prefix(width).enumerated() { buf[offset + i] = b }
    }

    private static func put(_ buf: inout [UInt8], _ offset: Int, _ width: Int, _ value: Int) {
        var v = value
        for i in stride(from: width - 1, through: 0, by: -1) {
            buf[offset + i] = UInt8(v & 0xFF)
            v >>= 8
        }
    }
}

public struct SystemInfo {
    public var name: String
    public var revision: String
    public var buildDate: String
}

/// The ASM protocol spoken by the Neo in comms mode.
/// Ported from neotools `device.py`, `message.py` and `file.py`.
public final class NeoDevice {
    let transport: NeoTransport
    static let minimumProtocolVersion = 0x0220
    static let defaultTimeout: TimeInterval = 1.0

    public init(transport: NeoTransport) {
        self.transport = transport
    }

    // MARK: Dialogue

    func dialogueStart(applet: Int = AppletID.system) throws {
        try hello()
        try reset()
        try switchApplet(applet)
    }

    func dialogueEnd() throws {
        try reset()
    }

    func reset() throws {
        try transport.write(Array("?\u{FF}\u{00}reset".unicodeScalars.map { UInt8($0.value) }), timeout: Self.defaultTimeout)
    }

    func switchApplet(_ applet: Int) throws {
        let request: [UInt8] = Array("?Swtch".utf8) + [UInt8(applet >> 8 & 0xFF), UInt8(applet & 0xFF)]
        try transport.write(request, timeout: Self.defaultTimeout)
        let response = try transport.read(8, timeout: Self.defaultTimeout)
        guard response == Array("Switched".utf8) else {
            throw NeoError.protocolError("Failed to switch to applet 0x\(String(applet, radix: 16))")
        }
    }

    /// Asks for the ASM protocol version. This also puts the Neo into ASM mode and
    /// works as a keep-alive.
    func hello() throws {
        var lastResponse: [UInt8] = []
        for _ in 0..<10 {
            do {
                try transport.write([0x01], timeout: 0.1)
                lastResponse = try transport.read(8, timeout: 0.1)
            } catch NeoError.timeout {
                lastResponse = []
            }
            if lastResponse.count == 2 {
                let version = Int(lastResponse[0]) << 8 | Int(lastResponse[1])
                guard version >= Self.minimumProtocolVersion else {
                    throw NeoError.protocolError("ASM protocol version 0x\(String(version, radix: 16)) isn't supported")
                }
                return
            }
            try? reset()
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw NeoError.protocolError("The Neo isn't responding")
    }

    // MARK: Messages

    @discardableResult
    func send(_ message: Message, expect: UInt8? = nil, timeout: TimeInterval = defaultTimeout) throws -> Message {
        try transport.write(message.bytes, timeout: timeout)
        return try receive(expect: expect, timeout: timeout)
    }

    func receive(expect: UInt8? = nil, timeout: TimeInterval = defaultTimeout) throws -> Message {
        let response = Message(raw: try transport.read(8, timeout: timeout))
        guard response.bytes.count == 8 else {
            throw NeoError.protocolError("Short response: \(response)")
        }
        if let expect, response.command != expect {
            throw NeoError.unexpectedResponse(expected: expect, got: response)
        }
        return response
    }

    func readExtendedData(size: Int) throws -> [UInt8] {
        var result: [UInt8] = []
        var remaining = size
        while remaining > 0 {
            let response = try send(Message(Command.blockRead))
            if response.command == Response.blockReadEmpty { break }
            guard response.command == Response.blockRead else {
                throw NeoError.unexpectedResponse(expected: Response.blockRead, got: response)
            }
            let blockSize = response.argument(1, 4)
            let checksum = response.argument(5, 2)
            let block = try transport.read(blockSize, timeout: Double(blockSize * 10 + 600) / 1000)
            let actual = dataChecksum(block)
            guard actual == checksum else { throw NeoError.checksumMismatch(expected: checksum, got: actual) }
            guard !block.isEmpty else { break }
            result += block
            remaining -= block.count
        }
        return result
    }

    func writeExtendedData(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let block = Array(bytes[offset..<min(offset + 0x400, bytes.count)])
            try send(Message(Command.blockWrite, [(block.count, 1, 4), (dataChecksum(block), 5, 2)]),
                     expect: Response.blockWrite)
            try transport.write(block, timeout: Self.defaultTimeout)
            _ = try receive(expect: Response.blockWriteDone)
            offset += block.count
        }
    }

    // MARK: System

    public func systemInfo() throws -> SystemInfo {
        try dialogueStart()
        let response = try send(Message(Command.version), expect: Response.version)
        let size = response.argument(1, 4)
        let buf = try transport.read(size, timeout: Self.defaultTimeout)
        try dialogueEnd()
        // Checksums aren't verified here: some Neo firmware gets this one wrong.
        func field(_ offset: Int, _ width: Int) -> String {
            guard buf.count >= offset + width else { return "" }
            let bytes = buf[offset..<offset + width].prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }
        let revision = buf.count > 5 ? "\(buf[4]).\(buf[5])" : "?"
        return SystemInfo(name: field(0x06, 19), revision: revision, buildDate: field(0x19, 39))
    }

    /// Restarts the Neo, which brings it back up in keyboard mode.
    public func restartToKeyboardMode() throws {
        try dialogueStart()
        // The Neo doesn't always answer a restart before it drops off the bus.
        _ = try? send(Message(Command.restart), expect: Response.restart)
        try? dialogueEnd()
    }

    // MARK: Files

    /// Attributes of the file at `index` (1-based), or nil if there is no such file.
    public func fileAttributes(applet: Int = AppletID.alphaWord, index: Int) throws -> FileAttributes? {
        try dialogueStart()
        let response = try send(Message(Command.getFileAttributes, [(index, 4, 1), (applet, 5, 2)]))
        if response.command == Response.errorParameter {
            return nil  // past the last file
        }
        guard response.command == Response.getFileAttributes else {
            throw NeoError.unexpectedResponse(expected: Response.getFileAttributes, got: response)
        }
        let length = response.argument(1, 4)
        let checksum = response.argument(5, 2)
        guard length == FileAttributes.size else {
            throw NeoError.protocolError("File attributes length \(length), expected \(FileAttributes.size)")
        }
        let buf = try transport.read(length, timeout: Self.defaultTimeout)
        let actual = dataChecksum(buf)
        guard actual == checksum else { throw NeoError.checksumMismatch(expected: checksum, got: actual) }
        try dialogueEnd()
        return try FileAttributes(index: index, raw: buf)
    }

    public func listFiles(applet: Int = AppletID.alphaWord) throws -> [FileAttributes] {
        var files: [FileAttributes] = []
        var index = 1
        while let attrs = try fileAttributes(applet: applet, index: index) {
            files.append(attrs)
            index += 1
        }
        return files.sorted { ($0.space, $0.name) < ($1.space, $1.name) }
    }

    /// The file's raw bytes, including any trailing padding.
    public func readFile(_ file: FileAttributes, applet: Int = AppletID.alphaWord) throws -> [UInt8] {
        try dialogueStart()
        try send(Message(Command.readRawFile, [(file.allocSize, 1, 3), (file.index, 4, 1), (applet, 5, 2)]))
        let data = try readExtendedData(size: file.allocSize)
        try dialogueEnd()
        return data
    }

    /// The file's text, decoded from AlphaWord's character set.
    public func readText(_ file: FileAttributes) throws -> String {
        AlphaWordText.decode(try readFile(file))
    }

    /// What an empty AlphaWord slot holds: 512 bytes of the 0xA7 padding byte.
    static let emptyFileContents = [UInt8](repeating: 0xA7, count: 512)

    /// Empties a slot by overwriting it with the same padding an untouched slot
    /// holds. Attributes are left alone. neotools instead zeroes the sizes, which
    /// leaves the slot in a state the Neo never produces itself.
    public func clearFile(_ file: FileAttributes, applet: Int = AppletID.alphaWord) throws {
        guard let current = try fileAttributes(applet: applet, index: file.index) else {
            throw NeoError.protocolError("File \(file.index) no longer exists")
        }
        guard current.space == file.space else {
            throw NeoError.protocolError("File \(file.index) moved from slot \(file.space) to \(current.space)")
        }
        try writeRawFile(index: file.index, bytes: Self.emptyFileContents, applet: applet)
    }

    func writeRawFile(index: Int, bytes: [UInt8], applet: Int) throws {
        try dialogueStart()
        try send(Message(Command.writeRawFile, [(index, 1, 1), (bytes.count, 2, 3), (applet, 5, 2)]),
                 expect: Response.writeFile)
        try writeExtendedData(bytes)
        try send(Message(Command.confirmWriteFile), expect: Response.confirmWriteFile)
        try dialogueEnd()
    }
}
