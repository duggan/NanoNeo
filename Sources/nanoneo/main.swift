import Foundation
import NeoKit

// Developer CLI for exercising NeoKit against real hardware.

let usage = """
usage: nanoneo <command>
  mode                     print keyboard / comms / absent
  info                     system name, revision and build date
  list                     AlphaWord files
  read <slot>              print a slot's text
  raw <slot> <path>        save a slot's raw bytes
  clear <slot> --yes       empty a slot (destructive)
  keyboard                 restart the Neo into keyboard mode
  sync [--dest DIR] [--state FILE] [--no-clear]
                           save each non-empty slot as a new file, then clear it
Commands other than `mode` switch the Neo into comms mode first.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func connect() throws -> NeoDevice {
    try ModeSwitch.enterCommsMode()
    return NeoDevice(transport: try USBHostTransport())
}

func file(_ device: NeoDevice, slot arg: String?) throws -> FileAttributes {
    guard let arg, let slot = Int(arg), (1...8).contains(slot) else { fail("slot must be 1–8") }
    guard let file = try device.listFiles().first(where: { $0.space == slot }) else { fail("no file in slot \(slot)") }
    return file
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "mode":
        print(ModeSwitch.currentMode().rawValue)
    case "info":
        let info = try connect().systemInfo()
        print("\(info.name) \(info.revision) (\(info.buildDate))")
    case "list":
        for f in try connect().listFiles() {
            print("slot \(f.space)  index \(f.index)  \(f.name)  alloc \(f.allocSize)  min \(f.minSize)  flags 0x\(String(f.flags, radix: 16))")
        }
    case "read":
        let device = try connect()
        print(try device.readText(try file(device, slot: args.dropFirst().first)), terminator: "")
    case "raw":
        let device = try connect()
        guard args.count == 3 else { fail(usage) }
        let bytes = try device.readFile(try file(device, slot: args[1]))
        try Data(bytes).write(to: URL(fileURLWithPath: args[2]))
        print("\(bytes.count) bytes")
    case "clear":
        guard args.contains("--yes") else { fail("clear is destructive; pass --yes") }
        let device = try connect()
        let f = try file(device, slot: args[1])
        try device.clearFile(f)
        print("cleared slot \(f.space)")
    case "keyboard":
        guard ModeSwitch.currentMode() == .comms else { print(ModeSwitch.currentMode().rawValue); break }
        try NeoDevice(transport: try USBHostTransport()).restartToKeyboardMode()
        print(ModeSwitch.waitForKeyboardMode() ? "keyboard" : "restart sent; still waiting for keyboard mode")
    case "sync":
        func option(_ name: String) -> URL? {
            args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? URL(fileURLWithPath: args[$0 + 1]) : nil }
        }
        let report = try NeoSession.sync(destination: option("--dest") ?? NeoSession.defaultDestination,
                                         stateURL: option("--state") ?? NeoSession.defaultStateURL,
                                         clearSlots: !args.contains("--no-clear"))
        for (slot, url) in report.saved { print("slot \(slot) → \(url.path)") }
        for slot in report.alreadySaved { print("slot \(slot) already saved") }
        if !report.cleared.isEmpty { print("cleared slots \(report.cleared.sorted())") }
        for (slot, message) in report.failures { print("slot \(slot): \(message)") }
        if !report.failures.isEmpty { exit(1) }
    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
