import Foundation

/// Reads AlphaWord slots from a connected Neo.
public final class NeoSlotSource: SlotSource {
    let device: NeoDevice
    private var files: [Int: FileAttributes] = [:]

    public init(device: NeoDevice) {
        self.device = device
    }

    public func readSlots() throws -> [Slot] {
        var slots: [Slot] = []
        for file in try device.listFiles() where (1...8).contains(file.space) {
            files[file.space] = file
            slots.append(Slot(number: file.space, text: try device.readText(file)))
        }
        return slots
    }

    public func clear(slot: Int) throws {
        guard let file = files[slot] else { throw NeoError.protocolError("Slot \(slot) wasn't read first") }
        try device.clearFile(file)
    }
}

/// One complete sync: switch the Neo to comms mode, run the inbox flow, then
/// restart the Neo back into keyboard mode. Blocks; call off the main thread.
public enum NeoSession {
    public static var defaultDestination: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Neo")
    }

    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NanoNeo")
    }

    public static var defaultStateURL: URL {
        supportDirectory.appendingPathComponent("state.json")
    }

    public static func sync(destination: URL = defaultDestination,
                            stateURL: URL = defaultStateURL,
                            clearSlots: Bool = true) throws -> SyncReport {
        try ModeSwitch.enterCommsMode()
        let device = NeoDevice(transport: try USBHostTransport())
        defer {
            try? device.restartToKeyboardMode()
            _ = ModeSwitch.waitForKeyboardMode()
        }
        var inbox = InboxSync(destination: destination, stateURL: stateURL)
        inbox.clearSlots = clearSlots
        return try inbox.run(source: NeoSlotSource(device: device))
    }
}
