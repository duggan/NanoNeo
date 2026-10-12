import AppKit
import Foundation
import NeoKit
import ServiceManagement
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var mode: NeoMode = .absent
    @Published private(set) var isSyncing = false {
        didSet { updateBlink() }
    }
    /// Toggles while syncing, to blink the menu bar icon's screen.
    @Published private(set) var syncBlink = false
    private var blinkTimer: Timer?
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastResult: String?
    @Published var autoSync: Bool {
        didSet { UserDefaults.standard.set(autoSync, forKey: DefaultsKey.autoSync) }
    }
    @Published var clearSlots: Bool {
        didSet { UserDefaults.standard.set(clearSlots, forKey: DefaultsKey.clearSlots) }
    }
    @Published var destination: URL {
        didSet { UserDefaults.standard.set(destination.path, forKey: DefaultsKey.destinationPath) }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let monitor = DeviceMonitor()
    /// Ignore keyboard-mode arrivals until this time. The Neo re-enumerates as a
    /// keyboard at the end of every sync, which mustn't trigger another one.
    private var ignoreArrivalsUntil = Date.distantPast

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [DefaultsKey.autoSync: true, DefaultsKey.clearSlots: true])
        autoSync = defaults.bool(forKey: DefaultsKey.autoSync)
        clearSlots = defaults.bool(forKey: DefaultsKey.clearSlots)
        destination = defaults.string(forKey: DefaultsKey.destinationPath)
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? NeoSession.defaultDestination
        lastSync = (try? InboxState.load(from: NeoSession.defaultStateURL))?.lastSync

        monitor.onChange = { [weak self] mode, arrived in
            self?.deviceChanged(mode: mode, arrivedInKeyboardMode: arrived)
        }
        monitor.start()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var hasSeenWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.hasSeenWelcome) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.hasSeenWelcome) }
    }

    /// Called once at launch. If the Neo is already plugged in, there's no arrival
    /// to react to, so sync now — unless the first-run welcome is up.
    func syncIfConnectedAtLaunch() {
        guard autoSync, hasSeenWelcome, mode != .absent else { return }
        // Same settling delay as a fresh plug-in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.autoSync else { return }
            self.syncNow()
        }
    }

    /// Asks for a new destination folder. Returns once the panel is dismissed.
    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where NanoNeo saves drafts from the Neo."
        panel.directoryURL = destination
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
        }
    }

    var statusText: String {
        if isSyncing { return "Syncing…" }
        switch mode {
        case .absent: return "Neo not connected"
        case .keyboard: return "Neo connected"
        case .comms: return "Neo connected (transfer mode)"
        }
    }

    var lastSyncText: String {
        guard let lastSync else { return "Never synced" }
        let when = lastSync.formatted(date: Calendar.current.isDateInToday(lastSync) ? .omitted : .abbreviated,
                                      time: .shortened)
        return "Last sync: \(when)" + (lastResult.map { " — \($0)" } ?? "")
    }

    private func updateBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        syncBlink = isSyncing
        guard isSyncing else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncBlink.toggle() }
        }
    }

    var canSync: Bool { mode != .absent && !isSyncing }

    private func deviceChanged(mode: NeoMode, arrivedInKeyboardMode: Bool) {
        self.mode = mode
        if arrivedInKeyboardMode, autoSync, !isSyncing, Date() >= ignoreArrivalsUntil {
            // Let the keyboard interface settle before switching modes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.syncNow() }
        }
    }

    func syncNow() {
        guard canSync else { return }
        isSyncing = true
        let destination = self.destination
        let clearSlots = self.clearSlots
        Task.detached(priority: .userInitiated) {
            let result = Result { try NeoSession.sync(destination: destination, clearSlots: clearSlots) }
            await self.finishSync(result)
        }
    }

    private func finishSync(_ result: Result<SyncReport, Error>) {
        isSyncing = false
        ignoreArrivalsUntil = Date().addingTimeInterval(10)
        mode = ModeSwitch.currentMode()
        switch result {
        case let .success(report):
            lastSync = Date()
            let count = report.saved.count
            lastResult = count == 0 ? "nothing new" : "\(count) draft\(count == 1 ? "" : "s") saved"
            if !report.failures.isEmpty {
                lastResult! += ", \(report.failures.count) problem\(report.failures.count == 1 ? "" : "s")"
                notify(title: "NanoNeo hit a problem",
                       body: report.failures.map { "Slot \($0.slot): \($0.message)" }.joined(separator: "\n"))
            } else if count > 0 {
                let titles = report.saved.map { $0.url.deletingPathExtension().lastPathComponent }
                notify(title: "Saved \(count) draft\(count == 1 ? "" : "s") from the Neo",
                       body: titles.joined(separator: "\n"))
            }
        case let .failure(error):
            lastResult = "failed"
            notify(title: "NanoNeo couldn't sync", body: String(describing: error))
        }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        NSWorkspace.shared.open(destination)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            notify(title: "Couldn't change Launch at Login", body: error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

enum DefaultsKey {
    static let autoSync = "autoSync"
    static let clearSlots = "clearSlots"
    static let destinationPath = "destinationPath"
    static let hasSeenWelcome = "hasSeenWelcome"
}
