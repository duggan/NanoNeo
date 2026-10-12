import CryptoKit
import Foundation

/// What the app remembers between syncs, stored as JSON outside iCloud.
/// For each slot it records the last text saved, so a slot whose clear failed
/// isn't saved twice.
public struct InboxState: Codable, Equatable {
    public struct SlotRecord: Codable, Equatable {
        public var sha256: String
        public var savedAs: String  // absolute path
        public var savedAt: Date
        public var clearedAt: Date?
    }

    public var slots: [String: SlotRecord] = [:]
    public var lastSync: Date?

    public init() {}

    public static func load(from url: URL) throws -> InboxState {
        guard FileManager.default.fileExists(atPath: url.path) else { return InboxState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InboxState.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
