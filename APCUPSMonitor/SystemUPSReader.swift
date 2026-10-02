import Foundation
import IOKit.ps

struct SystemUPSSnapshot: Codable {
    let name: String
    let batteryPercent: Int?
    let runtimeMinutes: Int?
    let powerSourceState: String
    let isOnBattery: Bool
    let rawDictionary: [String: String]
}

final class SystemUPSReader {
    func readUPS() -> SystemUPSSnapshot? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let unmanaged = IOPSGetPowerSourceDescription(snapshot, source),
                  let info = unmanaged.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let type = info[kIOPSTypeKey] as? String ?? ""
            let name = info[kIOPSNameKey] as? String ?? "Unknown UPS"

            // A connected USB UPS normally appears as a UPS type. Keep the name check as
            // a fallback for APC devices on macOS versions that expose a slightly different type.
            let looksLikeUPS = type.localizedCaseInsensitiveContains("UPS") ||
                name.localizedCaseInsensitiveContains("UPS") ||
                name.localizedCaseInsensitiveContains("Back-UPS")
            guard looksLikeUPS else { continue }

            let current = info[kIOPSCurrentCapacityKey] as? Int
            let max = info[kIOPSMaxCapacityKey] as? Int
            let batteryPercent: Int?
            if let current, let max, max > 0 {
                batteryPercent = Int((Double(current) / Double(max) * 100.0).rounded())
            } else {
                batteryPercent = current
            }

            let runtime = info[kIOPSTimeToEmptyKey] as? Int
            let state = info[kIOPSPowerSourceStateKey] as? String ?? "Unknown"
            let onBattery = state == kIOPSBatteryPowerValue

            var raw: [String: String] = [:]
            for (key, value) in info {
                raw[key] = String(describing: value)
            }

            return SystemUPSSnapshot(
                name: name,
                batteryPercent: batteryPercent,
                runtimeMinutes: runtime,
                powerSourceState: state,
                isOnBattery: onBattery,
                rawDictionary: raw
            )
        }

        return nil
    }
}
