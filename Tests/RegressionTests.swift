import Foundation
import AppKit
import Darwin

@main
struct RegressionTests {
    @MainActor
    static func main() async throws {
        let fixturePath = ProcessInfo.processInfo.environment["APC_TEST_FIXTURE"]
        if let argument = CommandLine.arguments.dropFirst().first, argument.hasPrefix("--read-") {
            let mode = try String(contentsOfFile: fixturePath!, encoding: .utf8)
            if mode == "hang" || (mode == "hang-hid" && argument == "--read-hid") {
                signal(SIGTERM, SIG_IGN)
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
            if mode == "malformed" {
                FileHandle.standardOutput.write(Data("not JSON".utf8))
            } else if argument == "--read-system" {
                let snapshot: SystemUPSSnapshot? = mode == "missing" ? nil : SystemUPSSnapshot(
                    name: "Test UPS", batteryPercent: 71, runtimeMinutes: 12,
                    powerSourceState: "Battery Power", isOnBattery: true,
                    rawDictionary: ["Name": "Test UPS"])
                FileHandle.standardOutput.write(try JSONEncoder().encode(snapshot))
            } else {
                let element = HIDElementSnapshot(id: "test", usagePage: 0x84, usage: 0x35,
                    value: 25, logicalMin: 0, logicalMax: 100, unit: 0, reportID: 1)
                let snapshot = HIDUPSSnapshot(status: "Shared HID OK", loadPercent: 25,
                                               lineVoltage: 120, elements: [element])
                FileHandle.standardOutput.write(try JSONEncoder().encode(snapshot))
            }
            return
        }

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        setenv("APC_TEST_FIXTURE", fixture.path, 1)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        func setMode(_ mode: String) throws { try mode.write(to: fixture, atomically: true, encoding: .utf8) }
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            print("PASS: \(message)")
        }
        func pause(_ seconds: Double = 0.1) async throws {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        func waitFor(_ condition: () -> Bool, seconds: Double = 3) async throws {
            let deadline = Date().addingTimeInterval(seconds)
            while !condition() && Date() < deadline { try await pause() }
            expect(condition(), "Async operation completed within \(seconds)s")
        }

        let reader = SnapshotProcess()
        try setMode("hang")
        var callbacks = 0
        var timedOut = false
        reader.read(executable: executable, argument: "--read-system", timeout: 0.25) { result in
            callbacks += 1
            if case .failure(let error) = result, case SnapshotProcess.ReadError.timeout = error {
                timedOut = true
            }
        }
        reader.read(executable: executable, argument: "--read-system") { _ in
            fatalError("Overlapping read should not start")
        }
        try await waitFor({ !reader.isRunning })
        expect(timedOut && callbacks == 1, "Hung child killed; one timeout callback; overlapping reads suppressed")

        try setMode("good")
        var recovered = false
        reader.read(executable: executable, argument: "--read-system") { result in
            recovered = (try? result.get()).flatMap { try? JSONDecoder().decode(SystemUPSSnapshot.self, from: $0) }?.batteryPercent == 71
        }
        try await waitFor({ !reader.isRunning })
        expect(recovered, "Same reader recovers after timeout")

        try setMode("hang")
        reader.read(executable: executable, argument: "--read-system") { _ in
            fatalError("Canceled read must not publish")
        }
        reader.cancel()
        try await waitFor({ !reader.isRunning })
        expect(true, "Cancellation reaps child and discards old result")

        var launchFailed = false
        reader.read(executable: URL(fileURLWithPath: "/nonexistent/apc-test"), argument: "--read-system") { result in
            if case .failure = result { launchFailed = true }
        }
        expect(launchFailed && !reader.isRunning, "Launch failure releases reader for retry")

        try setMode("good")
        let model = UPSMonitorModel(executable: executable, startAutomatically: false)
        model.refresh()
        try await waitFor({ model.batteryPercent == 71 && model.loadPercent == 25 })
        expect(model.estimatedWatts == 82.5 && model.isOnBattery, "System and HID snapshots populate model")
        try setMode("missing")
        model.refresh()
        try await waitFor({ model.batteryPercent == nil })
        expect(model.runtimeMinutes == nil && model.systemDictionary.isEmpty && model.lastSystemRead == nil,
               "Missing UPS clears stale readings and timestamp")
        try await pause(0.3)
        try setMode("malformed")
        model.refresh()
        try await waitFor({ model.loadPercent == nil })
        expect(model.estimatedWatts == nil && model.hidElements.isEmpty, "Malformed HID clears stale readings")
        try await pause(0.3)
        try setMode("hang-hid")
        model.refresh()
        try await waitFor({ model.batteryPercent == 71 })
        expect(model.lastSystemRead != nil, "Hanging HID does not block system data")
        try await waitFor({ model.hidStatus.contains("timed out") }, seconds: 7)
        try await pause(0.3)
        try setMode("good")
        model.refresh()
        try await waitFor({ model.loadPercent == 25 })
        expect(true, "Manual refresh recovers HID after timeout")
        model.prepareForSleep()
        expect(model.batteryPercent == nil && model.loadPercent == nil, "Sleep invalidates old values")
        try await pause(0.3)
        model.resumeAfterWake()
        try await waitFor({ model.batteryPercent == 71 && model.loadPercent == 25 })
        expect(true, "Wake resumes both channels")

        try setMode("hang")
        let automatic = UPSMonitorModel(executable: executable)
        try await waitFor({ automatic.systemStatus.contains("timed out") }, seconds: 7)
        try setMode("good")
        try await waitFor({ automatic.batteryPercent == 71 }, seconds: 5)
        expect(true, "Timer automatically recovers system reads after timeout without Refresh")
        automatic.prepareForSleep()
        print("All regression tests passed")
    }
}
