import Foundation
import Combine
import AppKit

@MainActor
final class UPSMonitorModel: ObservableObject {
    @Published var deviceName = "APC UPS"
    @Published var batteryPercent: Int?
    @Published var runtimeMinutes: Int?
    @Published var powerSourceState = "Unknown"
    @Published var isOnBattery = false
    @Published var loadPercent: Double?
    @Published var estimatedWatts: Double?
    @Published var lineVoltage: Double?
    @Published var hidStatus = "Not started"
    @Published var systemDictionary: [String: String] = [:]
    @Published var hidElements: [HIDElementSnapshot] = []

    @Published var systemStatus = "Waiting for first read"
    @Published var lastSystemRead: Date?
    @Published var lastHIDRead: Date?

    private let systemProcess = SnapshotProcess()
    private let hidProcess = SnapshotProcess()
    private let executable: URL
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var terminationObserver: NSObjectProtocol?
    private var nextHIDRead = Date.distantPast
    private var sleeping = false

    // Back-UPS ES 600M1 rated active power.
    let nominalWatts: Double = 330

    init(executable: URL = Bundle.main.executableURL!, startAutomatically: Bool = true) {
        self.executable = executable
        guard startAutomatically else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The notification is delivered synchronously on the main thread;
            // terminate workers before AppKit exits (an async Task is too late).
            MainActor.assumeIsolated {
                self?.systemProcess.cancel()
                self?.hidProcess.cancel()
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepareForSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterWake() }
        })
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        // Continue polling while a menu or another tracking UI is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    deinit {
        timer?.invalidate()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    var menuTitle: String {
        if let watts = estimatedWatts {
            return String(format: "%.0f W", watts)
        }
        if let loadPercent {
            return String(format: "%.0f%%", loadPercent)
        }
        if let batteryPercent {
            return "UPS \(batteryPercent)%"
        }
        return "UPS"
    }

    func refresh() {
        nextHIDRead = .distantPast
        poll()
    }

    func prepareForSleep() {
        sleeping = true
        systemProcess.cancel()
        hidProcess.cancel()
        clearSystem(status: "Sleeping; waiting for wake")
        clearHID(status: "Sleeping; waiting for wake")
    }

    func resumeAfterWake() {
        sleeping = false
        refresh()
    }

    private func poll() {
        guard !sleeping else { return }
        if !systemProcess.isRunning {
            systemProcess.read(executable: executable, argument: "--read-system") { [weak self] result in
                self?.receiveSystem(result)
            }
        }
        if !hidProcess.isRunning && Date() >= nextHIDRead {
            hidProcess.read(executable: executable, argument: "--read-hid") { [weak self] result in
                self?.receiveHID(result)
            }
        }
    }

    private func receiveSystem(_ result: Result<Data, Error>) {
        do {
            let data = try result.get()
            guard let system = try JSONDecoder().decode(SystemUPSSnapshot?.self, from: data) else {
                clearSystem(status: "UPS not found; retrying automatically")
                return
            }
            deviceName = system.name
            batteryPercent = system.batteryPercent
            runtimeMinutes = system.runtimeMinutes.flatMap { $0 >= 0 ? $0 : nil }
            powerSourceState = system.powerSourceState
            isOnBattery = system.isOnBattery
            systemDictionary = system.rawDictionary
            systemStatus = "macOS read OK"
            lastSystemRead = Date()
        } catch {
            clearSystem(status: error.localizedDescription)
        }
    }

    private func receiveHID(_ result: Result<Data, Error>) {
        do {
            let hid = try JSONDecoder().decode(HIDUPSSnapshot.self, from: result.get())
            hidStatus = hid.status
            hidElements = hid.elements
            loadPercent = hid.loadPercent
            estimatedWatts = hid.loadPercent.map { nominalWatts * $0 / 100 }
            lineVoltage = hid.lineVoltage
            // Access denial is independent of the native macOS UPS data.
            // Back off, then rediscover using a fresh process/manager.
            let hasValues = !hid.elements.isEmpty
            lastHIDRead = hasValues ? Date() : nil
            nextHIDRead = Date().addingTimeInterval(hasValues ? 2 : 30)
        } catch {
            clearHID(status: error.localizedDescription)
            nextHIDRead = Date().addingTimeInterval(30)
        }
    }

    private func clearSystem(status: String) {
        deviceName = "APC UPS"
        batteryPercent = nil
        runtimeMinutes = nil
        powerSourceState = "Unknown"
        isOnBattery = false
        systemDictionary = [:]
        systemStatus = status
        lastSystemRead = nil
    }

    private func clearHID(status: String) {
        hidStatus = status
        hidElements = []
        loadPercent = nil
        estimatedWatts = nil
        lineVoltage = nil
        lastHIDRead = nil
    }
}
