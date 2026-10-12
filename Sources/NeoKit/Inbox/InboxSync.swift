import Foundation

public struct Slot: Equatable {
    public var number: Int
    public var text: String

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
}

/// Where slots come from and how they're cleared. `NeoSlotSource` talks to the
/// device; tests use a fake.
public protocol SlotSource {
    func readSlots() throws -> [Slot]
    func clear(slot: Int) throws
}

public struct SyncReport: Equatable {
    /// Newly saved files, by slot.
    public var saved: [(slot: Int, url: URL)] = []
    /// Slots whose text had already been saved by an earlier sync whose clear failed.
    public var alreadySaved: [Int] = []
    public var cleared: [Int] = []
    public var failures: [(slot: Int, message: String)] = []

    public static func == (a: SyncReport, b: SyncReport) -> Bool {
        a.saved.map(\.slot) == b.saved.map(\.slot) && a.saved.map(\.url) == b.saved.map(\.url)
            && a.alreadySaved == b.alreadySaved && a.cleared == b.cleared
            && a.failures.map(\.slot) == b.failures.map(\.slot)
    }
}

/// The inbox flow. For each non-empty slot: save the text as a new file, read it
/// back to check it, and only then clear the slot.
public struct InboxSync {
    public var destination: URL
    public var stateURL: URL
    public var clearSlots = true
    public var now: () -> Date = Date.init

    public init(destination: URL, stateURL: URL) {
        self.destination = destination
        self.stateURL = stateURL
    }

    public func run(source: SlotSource) throws -> SyncReport {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var state = try InboxState.load(from: stateURL)
        var report = SyncReport()
        let date = now()

        var toClear: [Int] = []
        for slot in try source.readSlots().sorted(by: { $0.number < $1.number }) {
            guard !slot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let data = Data(slot.text.utf8)
            let hash = InboxState.hash(data)
            let key = String(slot.number)

            if let record = state.slots[key], record.sha256 == hash, Self.file(atPath: record.savedAs, hasHash: hash) {
                report.alreadySaved.append(slot.number)
                toClear.append(slot.number)
                continue
            }
            do {
                let url = try Self.writeNewFile(data, in: destination,
                                                baseName: InboxNaming.baseName(for: slot.text, date: date))
                state.slots[key] = .init(sha256: hash, savedAs: url.path, savedAt: date)
                try state.save(to: stateURL)
                report.saved.append((slot.number, url))
                toClear.append(slot.number)
            } catch {
                report.failures.append((slot.number, "Couldn't save: \(error.localizedDescription)"))
            }
        }

        if clearSlots {
            // Highest first: the Neo opens on the last slot written, so it ends up
            // on the lowest cleared slot.
            for number in toClear.sorted(by: >) {
                do {
                    try source.clear(slot: number)
                    state.slots[String(number)]?.clearedAt = now()
                    report.cleared.append(number)
                } catch {
                    report.failures.append((number, "Saved, but couldn't clear the slot: \(error)"))
                }
            }
        }
        state.lastSync = date
        try state.save(to: stateURL)
        return report
    }

    static func file(atPath path: String, hasHash hash: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path) else { return false }
        return InboxState.hash(data) == hash
    }

    /// Writes `data` to a new file named after `baseName`, never replacing an
    /// existing file. The data is flushed to disk and read back before returning.
    static func writeNewFile(_ data: Data, in directory: URL, baseName: String) throws -> URL {
        let temp = directory.appendingPathComponent(".nanoneo-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temp.path])
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        let handle = try FileHandle(forWritingTo: temp)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()

        for name in InboxNaming.candidates(base: baseName) {
            let url = directory.appendingPathComponent(name)
            if renamex_np(temp.path, url.path, UInt32(RENAME_EXCL)) == 0 {
                fsyncDirectory(directory)
                guard FileManager.default.contents(atPath: url.path) == data else {
                    throw CocoaError(.fileWriteUnknown, userInfo: [
                        NSFilePathErrorKey: url.path,
                        NSLocalizedDescriptionKey: "\(name) didn't read back the same as the Neo's text",
                    ])
                }
                return url
            }
            guard errno == EEXIST else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        fatalError("unreachable: candidates is infinite")
    }

    private static func fsyncDirectory(_ url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        fsync(fd)
        close(fd)
    }
}
