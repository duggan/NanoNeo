import Foundation
import IOKit
import IOKit.usb
import NeoKit

/// Watches for the Neo arriving and leaving, in either USB mode, using IOKit
/// matching notifications delivered on the main queue.
final class DeviceMonitor {
    /// Called with the new mode whenever the Neo appears or disappears.
    /// `arrivedInKeyboardMode` is true only when a keyboard-mode Neo has just been
    /// plugged in (not for devices already present when monitoring started).
    var onChange: ((_ mode: NeoMode, _ arrivedInKeyboardMode: Bool) -> Void)?

    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    func start() {
        guard port == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)
        self.port = port

        for product in [USBIDs.keyboardProduct, USBIDs.commsProduct] {
            for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                let matching = [
                    kIOProviderClassKey: "IOUSBHostDevice",
                    kUSBVendorID: USBIDs.vendor,
                    kUSBProductID: product,
                ] as CFDictionary
                // Retained for the app's lifetime; the notification holds it as refcon.
                let context = Unmanaged.passRetained(Context(monitor: self, product: product, type: type))
                var iterator: io_iterator_t = 0
                IOServiceAddMatchingNotification(port, type, matching, { refcon, iterator in
                    guard let refcon else { return }
                    let ctx = Unmanaged<Context>.fromOpaque(refcon).takeUnretainedValue()
                    ctx.monitor?.handle(iterator: iterator, context: ctx, initial: false)
                }, context.toOpaque(), &iterator)
                iterators.append(iterator)
                // Drain existing matches; this also arms the notification.
                handle(iterator: iterator, context: context.takeUnretainedValue(), initial: true)
            }
        }
        onChange?(ModeSwitch.currentMode(), false)
    }

    private final class Context {
        weak var monitor: DeviceMonitor?
        let product: Int
        let type: String
        init(monitor: DeviceMonitor, product: Int, type: String) {
            self.monitor = monitor
            self.product = product
            self.type = type
        }
    }

    private func handle(iterator: io_iterator_t, context: Context, initial: Bool) {
        var any = false
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            IOObjectRelease(service)
            any = true
        }
        guard any, !initial else { return }
        let arrived = context.type == kIOFirstMatchNotification && context.product == USBIDs.keyboardProduct
        // A terminated device can linger in the registry briefly, so look again shortly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.onChange?(ModeSwitch.currentMode(), arrived)
        }
    }
}
