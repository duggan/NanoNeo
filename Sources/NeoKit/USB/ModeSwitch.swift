import Foundation
import IOKit
import IOKit.usb
import IOUSBHost

public enum NeoMode: String {
    case keyboard, comms, absent
}

/// Detects the Neo's USB mode and switches it from keyboard to comms mode.
public enum ModeSwitch {
    public static func currentMode() -> NeoMode {
        if isPresent(product: USBIDs.commsProduct) { return .comms }
        if isPresent(product: USBIDs.keyboardProduct) { return .keyboard }
        return .absent
    }

    /// Puts the Neo into comms mode, if it isn't already, and waits for it to re-enumerate.
    /// The Neo takes about 2.6 s; if it hasn't appeared after 4 s, flip once more.
    public static func enterCommsMode() throws {
        switch currentMode() {
        case .comms: return
        case .absent: throw NeoError.deviceNotFound
        case .keyboard: break
        }
        for _ in 0..<2 {
            try sendFlipReports()
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
                if currentMode() == .comms {
                    // Give the interface nub a moment to register.
                    Thread.sleep(forTimeInterval: 0.2)
                    return
                }
            }
        }
        throw NeoError.flipFailed
    }

    /// Waits until the Neo shows up in keyboard mode (after a restart), or the timeout passes.
    public static func waitForKeyboardMode(timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentMode() == .keyboard { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Sends HID SET_REPORT output reports 0xE0…0xE4 (values from a bus trace of
    /// the official tools; see neotools `device.py`). They go out as raw control
    /// requests on the device's default pipe through IOUSBHost, rather than through
    /// the HID keyboard interface. Opening a keyboard through IOHID needs Input
    /// Monitoring permission; this route needs no permission and no root.
    static func sendFlipReports() throws {
        let matching = [
            kIOProviderClassKey: "IOUSBHostDevice",
            kUSBVendorID: USBIDs.vendor,
            kUSBProductID: USBIDs.keyboardProduct,
        ] as CFDictionary
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { throw NeoError.deviceNotFound }
        defer { IOObjectRelease(service) }

        let device: IOUSBHostDevice
        do {
            device = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch {
            throw NeoError.usb("opening the Neo", error)
        }
        defer { device.destroy() }

        for value: UInt8 in [0xE0, 0xE1, 0xE2, 0xE3, 0xE4] {
            var request = IOUSBDeviceRequest()
            request.bmRequestType = 0x21  // host-to-device, class, interface
            request.bRequest = 0x09       // HID SET_REPORT
            request.wValue = 0x0200       // output report, ID 0
            request.wIndex = 0            // keyboard interface
            request.wLength = 1
            let data = NSMutableData(bytes: [value], length: 1)
            var sent = 0
            do {
                try device.__send(request, data: data, bytesTransferred: &sent, completionTimeout: 1)
            } catch {
                // The last report makes the Neo drop off the bus, so it may not be acknowledged.
                if value != 0xE4 { throw NeoError.usb("sending the mode-switch request", error) }
            }
        }
    }

    static func isPresent(product: Int) -> Bool {
        let matching = [
            kIOProviderClassKey: "IOUSBHostDevice",
            kUSBVendorID: USBIDs.vendor,
            kUSBProductID: product,
        ] as CFDictionary
        let s = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard s != IO_OBJECT_NULL else { return false }
        IOObjectRelease(s)
        return true
    }
}
