import Foundation
import IOKit
import IOKit.usb
import IOUSBHost

/// Bulk transport to the Neo in comms mode (product 0xBD01), using interface 0.
/// No kernel driver claims this interface, so it opens without root.
public final class USBHostTransport: NeoTransport {
    private let interface: IOUSBHostInterface
    private let inPipe: IOUSBHostPipe
    private let outPipe: IOUSBHostPipe
    private let packet = 8

    public init() throws {
        let matching = [
            kIOProviderClassKey: "IOUSBHostInterface",
            kUSBVendorID: USBIDs.vendor,
            kUSBProductID: USBIDs.commsProduct,
            kUSBConfigurationValue: 1,
            kUSBInterfaceNumber: 0,
        ] as CFDictionary
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { throw NeoError.deviceNotFound }
        defer { IOObjectRelease(service) }

        do {
            interface = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch {
            throw NeoError.usb("opening the Neo's interface", error)
        }

        var inAddress: UInt8?
        var outAddress: UInt8?
        let config = interface.configurationDescriptor
        let iface = interface.interfaceDescriptor
        var endpoint = IOUSBGetNextEndpointDescriptor(config, iface, nil)
        while let ep = endpoint {
            let address = ep.pointee.bEndpointAddress
            let isBulk = ep.pointee.bmAttributes & 0x03 == 0x02
            if isBulk {
                if address & 0x80 != 0 {
                    inAddress = inAddress ?? address
                } else {
                    outAddress = outAddress ?? address
                }
            }
            endpoint = IOUSBGetNextEndpointDescriptor(config, iface, UnsafePointer(OpaquePointer(ep)))
        }
        guard let inAddress, let outAddress else {
            interface.destroy()
            throw NeoError.protocolError("The Neo's bulk endpoints weren't found")
        }
        do {
            inPipe = try interface.copyPipe(withAddress: Int(inAddress))
            outPipe = try interface.copyPipe(withAddress: Int(outAddress))
        } catch {
            interface.destroy()
            throw NeoError.usb("opening the Neo's endpoints", error)
        }
    }

    deinit {
        interface.destroy()
    }

    public func write(_ bytes: [UInt8], timeout: TimeInterval) throws {
        var offset = 0
        while offset < bytes.count {
            let chunk = Array(bytes[offset..<min(offset + packet, bytes.count)])
            guard let data = try? interface.ioData(withCapacity: chunk.count) else {
                throw NeoError.usb("allocating a buffer", nil)
            }
            chunk.withUnsafeBytes { data.mutableBytes.copyMemory(from: $0.baseAddress!, byteCount: chunk.count) }
            var sent = 0
            do {
                try outPipe.__sendIORequest(with: data, bytesTransferred: &sent, completionTimeout: timeout)
            } catch {
                throw Self.map(error, "write")
            }
            offset += chunk.count
        }
    }

    public func read(_ count: Int, timeout: TimeInterval) throws -> [UInt8] {
        var result: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            let size = min(packet, remaining)
            guard let data = try? interface.ioData(withCapacity: size) else {
                throw NeoError.usb("allocating a buffer", nil)
            }
            var received = 0
            do {
                try inPipe.__sendIORequest(with: data, bytesTransferred: &received, completionTimeout: timeout)
            } catch {
                throw Self.map(error, "read")
            }
            result.append(contentsOf: UnsafeRawBufferPointer(start: data.bytes, count: received))
            remaining -= received
            if received != packet { break }  // short packet ends the transfer
        }
        return result
    }

    private static func map(_ error: Error, _ what: String) -> NeoError {
        let code = Int32(truncatingIfNeeded: (error as NSError).code)
        let transactionTimeout = Int32(bitPattern: 0xE000_4051)  // kIOUSBTransactionTimeout
        if code == kIOReturnTimeout || code == transactionTimeout {
            return .timeout
        }
        return .usb(what, error)
    }
}
