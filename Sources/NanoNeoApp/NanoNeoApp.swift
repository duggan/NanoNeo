import AppKit
import NeoKit
import SwiftUI

@main
struct NanoNeoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model, openSettings: appDelegate.showSettings)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private lazy var settings: WindowPresenter = WindowPresenter(title: "NanoNeo Settings") { [model] in
        AnyView(SettingsView(model: model))
    }
    private lazy var welcome: WindowPresenter = WindowPresenter(title: "Welcome to NanoNeo") { [unowned self] in
        AnyView(WelcomeView(model: model, done: { self.welcome.close() }))
    }

    private var isTerminating = false

    override init() {
        // Checked before the model exists, so a second copy never starts
        // watching for the Neo.
        Self.exitIfAlreadyRunning()
        LegacyMigration.run()
        model = AppModel()
        super.init()
    }

    /// Two copies would both try to sync when the Neo is plugged in. If another
    /// NanoNeo is already running (from any location), hand over to it and quit.
    private static func exitIfAlreadyRunning() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0 != NSRunningApplication.current }
        guard let running = others.first else { return }
        running.activate()
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if model.hasSeenWelcome {
            model.syncIfConnectedAtLaunch()
        } else {
            // Done or the close button counts as seen; quitting with it open doesn't.
            welcome.onClose = { [unowned self] in
                if !isTerminating { model.hasSeenWelcome = true }
            }
            welcome.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
    }

    func showSettings() {
        settings.show()
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // While syncing, the Neo's screen blinks on and off.
        if let icon = model.isSyncing && model.syncBlink ? MenuBarIcon.syncing : MenuBarIcon.idle {
            Image(nsImage: icon)
        } else {
            Image(systemName: model.isSyncing ? "arrow.triangle.2.circlepath" : "keyboard")
        }
    }
}

/// The menu bar icons from the app bundle (`MenuBarIconTemplate.png` and
/// `MenuBarIconSyncingTemplate.png`, each with `@2x`), or nil to fall back to SF Symbols.
enum MenuBarIcon {
    static let idle = load("MenuBarIconTemplate")
    static let syncing = load("MenuBarIconSyncingTemplate")

    private static func load(_ name: String) -> NSImage? {
        guard let image = Bundle.main.image(forResource: name) else { return nil }
        image.isTemplate = true
        let height: CGFloat = 18
        if image.size.height > 0 {
            image.size = NSSize(width: image.size.width * height / image.size.height, height: height)
        }
        return image
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        Text(model.statusText)
        Text(model.lastSyncText)
        Divider()
        Button("Sync Now") { model.syncNow() }
            .keyboardShortcut("s")
            .disabled(!model.canSync)
        Button("Open Folder") { model.openFolder() }
            .keyboardShortcut("o")
        Button("Settings…") { openSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit NanoNeo") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
