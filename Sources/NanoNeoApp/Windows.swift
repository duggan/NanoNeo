import AppKit
import SwiftUI

/// Shows a SwiftUI view in a small, reusable AppKit window. NanoNeo is a menu
/// bar app (LSUIElement), so it activates itself first or the window would open
/// behind whatever app is in front.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let title: String
    private let content: () -> AnyView
    private var window: NSWindow?

    init(title: String, content: @escaping () -> AnyView) {
        self.title = title
        self.content = content
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: content())
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose?()
    }
}

/// "Save drafts to: ~/Documents/Neo  [Choose…]"
struct DestinationRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        LabeledContent("Save drafts to") {
            HStack(spacing: 8) {
                Text((model.destination.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(model.destination.path)
                Button("Choose…") { model.chooseDestination() }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                DestinationRow(model: model)
                Toggle(isOn: $model.clearSlots) {
                    Text("Clear slots on the Neo after saving")
                    Text("Each slot is cleared only after its text has been saved and checked.")
                }
            }
            Section {
                Toggle("Sync automatically when the Neo is connected", isOn: $model.autoSync)
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                Text("Welcome to NanoNeo")
                    .font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Plug in your AlphaSmart Neo and NanoNeo saves each AlphaWord file that has text in it as a new text file in your folder.")
                Text("By default it then clears that slot on the Neo, so the Neo works like an inbox: write, plug in, and find your drafts on the Mac.")
                Text("There are no permissions to grant and no drivers to install.")
            }
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            DestinationRow(model: model)

            Picker("After saving", selection: $model.clearSlots) {
                Text("Clear slots after saving (recommended)").tag(true)
                Text("Keep slots on the Neo").tag(false)
            }
            .pickerStyle(.radioGroup)

            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                    set: { model.setLaunchAtLogin($0) }))

            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
