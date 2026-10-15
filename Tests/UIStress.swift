import AppKit
import SwiftUI
import Darwin

/// Run in a logged-in macOS desktop. --legacy reproduces the old MenuBarExtra;
/// without it the exact production StatusItemController is exercised.
@MainActor
private enum Driver {
    static let preferenceDomain = "APCUPSMonitor.UIStress.\(getpid())"
    static let preferences = UserDefaults(suiteName: preferenceDomain)!
    static let model = UPSMonitorModel(executable: URL(fileURLWithPath: "/usr/bin/false"),
                                       startAutomatically: false, preferences: preferences)
    static var timer: Timer?
    static var warmFootprint: UInt64 = 0
    static var cycle = 0
    static var controller: StatusItemController?
    static let legacy = CommandLine.arguments.contains("--legacy")
    static let panel = CommandLine.arguments.contains("--panel")

    static func footprint() -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        precondition(result == 0)
        return info.ri_phys_footprint
    }

    static func start() {
        model.showMenuBarData = true
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    static func tick() {
        cycle += 1
        model.deviceName = "Memory Test UPS"
        model.batteryPercent = 100
        model.runtimeMinutes = 27
        model.powerSourceState = "AC Power"
        model.isOnBattery = false
        model.systemDictionary = ["Battery": "100", "Name": "Memory Test UPS"]
        model.systemStatus = "macOS read OK"
        model.lastSystemRead = Date()
        model.hidStatus = "Shared HID OK"
        model.hidElements = []
        model.loadPercent = Double(cycle % 30)
        model.estimatedWatts = Double(cycle % 30) * 3.3
        model.lineVoltage = 120
        model.lastHIDRead = Date()
        // Repeatedly exercise hosting graph creation and disposal as well.
        if panel && cycle % 100 == 1 { controller?.togglePopover() }
        if cycle == 500 { warmFootprint = footprint() }
        if cycle % 500 == 0 {
            print("mode=\(legacy ? "legacy" : "appkit") cycle=\(cycle) footprintMiB=\(Double(footprint()) / 1048576)")
            fflush(stdout)
        }
        if cycle == 5000 {
            let growth = Double(Int64(footprint()) - Int64(warmFootprint)) / 1048576
            print("growthAfterWarmupMiB=\(growth)")
            fflush(stdout)
            timer?.invalidate()
            preferences.removePersistentDomain(forName: preferenceDomain)
            if !legacy { precondition(growth < 10, "UI memory grew more than 10 MiB after warmup") }
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct LegacyApp: App {
    @StateObject var model = Driver.model
    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model).frame(width: 320)
        } label: {
            Label(model.menuTitle, systemImage: model.isOnBattery ? "battery.75percent" : "bolt.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@main
struct UIStress {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Driver.start()
        if Driver.legacy {
            LegacyApp.main()
        } else {
            let controller = StatusItemController(model: Driver.model)
            Driver.controller = controller
            NSApplication.shared.delegate = controller
            NSApplication.shared.run()
        }
    }
}
