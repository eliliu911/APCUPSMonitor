import Foundation
import IOKit.hid

struct HIDElementSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let usagePage: UInt32
    let usage: UInt32
    let value: Int64
    let logicalMin: Int64
    let logicalMax: Int64
    let unit: UInt32
    let reportID: UInt32

    var usageHex: String {
        String(format: "0x%02X:0x%02X", usagePage, usage)
    }
}

struct HIDUPSSnapshot: Codable {
    let status: String
    let loadPercent: Double?
    let lineVoltage: Double?
    let elements: [HIDElementSnapshot]
}

final class HIDUPSReader {
    private var manager: IOHIDManager?
    private let vendorID = 0x051D // American Power Conversion
    private let productID = 0x0002 // Back-UPS ES 600M1 in this unit

    func start() {
        guard manager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // IMPORTANT: kIOHIDOptionsTypeNone is shared, non-exclusive access.
        // We intentionally never use kIOHIDOptionsTypeSeizeDevice, so macOS ioupsd remains owner/manager.
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }

        self.manager = manager
    }

    func stop() {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    func readSnapshot() -> HIDUPSSnapshot {
        guard let manager else {
            return HIDUPSSnapshot(status: "Shared HID open failed", loadPercent: nil, lineVoltage: nil, elements: [])
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            return HIDUPSSnapshot(status: "UPS not found", loadPercent: nil, lineVoltage: nil, elements: [])
        }

        var allElements: [HIDElementSnapshot] = []
        var bestLoad: Double?
        var bestVoltage: Double?
        var openedAtLeastOne = false

        for device in devices {
            // Open the device SHARED. This is deliberately *not* kIOHIDOptionsTypeSeizeDevice.
            // If macOS refuses shared access, we back off rather than taking ownership from ioupsd.
            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else { continue }
            openedAtLeastOne = true
            defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

            guard let elements = IOHIDDeviceCopyMatchingElements(
                device,
                nil,
                IOOptionBits(kIOHIDOptionsTypeNone)
            ) as? [IOHIDElement] else {
                continue
            }

            for element in elements {
                let page = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)
                let elementType = IOHIDElementGetType(element)

                // Collections do not carry a scalar value.
                if elementType == kIOHIDElementTypeCollection { continue }

                var valueRef: Unmanaged<IOHIDValue>?
                let result = withUnsafeMutablePointer(to: &valueRef) { ptr in
                    ptr.withMemoryRebound(to: Unmanaged<IOHIDValue>.self, capacity: 1) { typedPtr in
                        IOHIDDeviceGetValue(device, element, typedPtr)
                    }
                }
                guard result == kIOReturnSuccess, let valueRef else { continue }

                let value = Int64(IOHIDValueGetIntegerValue(valueRef.takeUnretainedValue()))
                let logicalMin = Int64(IOHIDElementGetLogicalMin(element))
                let logicalMax = Int64(IOHIDElementGetLogicalMax(element))
                let unit = IOHIDElementGetUnit(element)
                let reportID = UInt32(IOHIDElementGetReportID(element))

                allElements.append(HIDElementSnapshot(
                    id: "\(page)-\(usage)-\(reportID)-\(IOHIDElementGetCookie(element))",
                    usagePage: page,
                    usage: usage,
                    value: value,
                    logicalMin: logicalMin,
                    logicalMax: logicalMax,
                    unit: unit,
                    reportID: reportID
                ))

                // USB HID Power Device Usage Page (0x84), PercentLoad (0x35).
                if page == 0x84 && usage == 0x35 {
                    let candidate = Double(value)
                    if candidate >= 0 && candidate <= 100 {
                        bestLoad = candidate
                    }
                }

                // Power Device Usage Page (0x84), Voltage (0x30).
                // The descriptor can contain multiple voltage elements; prefer a plausible US line value.
                if page == 0x84 && usage == 0x30 {
                    let candidates = scaledCandidates(value: value, element: element)
                    if let plausible = candidates.first(where: { $0 >= 80 && $0 <= 150 }) {
                        bestVoltage = plausible
                    }
                }
            }
        }

        allElements.sort {
            if $0.usagePage != $1.usagePage { return $0.usagePage < $1.usagePage }
            if $0.usage != $1.usage { return $0.usage < $1.usage }
            return $0.reportID < $1.reportID
        }

        let status: String
        if !openedAtLeastOne {
            status = "macOS denied shared HID access"
        } else if allElements.isEmpty {
            status = "HID read failed; retrying automatically"
        } else if bestLoad != nil {
            status = "Shared HID OK"
        } else {
            status = "Shared HID OK; load not mapped"
        }

        return HIDUPSSnapshot(status: status, loadPercent: bestLoad, lineVoltage: bestVoltage, elements: allElements)
    }

    private func scaledCandidates(value: Int64, element: IOHIDElement) -> [Double] {
        // APC HID reports sometimes include unit exponent scaling. For diagnostics we keep
        // conservative candidates so a raw 109, 1090, or 10900 can all map to 109 V.
        let raw = Double(value)
        return [raw, raw / 10.0, raw / 100.0, raw / 1000.0]
    }
}
