import AppKit
import Foundation
import NeoKit

/// NanoNeo was called NeoSync (bundle ID `ie.duggan.NeoSync`) up to 1.0.1. On the
/// first launch after the rename, this quits a running NeoSync, copies its settings
/// and moves its Application Support folder (sync state), so nothing is lost.
enum LegacyMigration {
    static let oldBundleID = "ie.duggan.NeoSync"
    private static let doneKey = "migratedFromNeoSync"
    private static let settingKeys = ["autoSync", "clearSlots", "destinationPath", "hasSeenWelcome"]

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // The old app would also sync when the Neo is plugged in, and it may be
        // writing the state we're about to move.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: oldBundleID) {
            app.terminate()
        }
        let deadline = Date().addingTimeInterval(3)
        while !NSRunningApplication.runningApplications(withBundleIdentifier: oldBundleID).isEmpty,
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        for key in settingKeys where defaults.object(forKey: key) == nil {
            if let value = CFPreferencesCopyAppValue(key as CFString, oldBundleID as CFString) {
                defaults.set(value, forKey: key)
            }
        }

        let fm = FileManager.default
        let old = NeoSession.supportDirectory.deletingLastPathComponent().appendingPathComponent("NeoSync")
        let new = NeoSession.supportDirectory
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
    }
}
