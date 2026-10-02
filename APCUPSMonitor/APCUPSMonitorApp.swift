import SwiftUI

@main
enum APCUPSMonitorEntry {
    static func main() {
        // A fresh, short-lived process owns each read. A stuck driver call can
        // then be terminated without freezing the UI or retaining stale handles.
        do {
            if CommandLine.arguments.contains("--read-system") {
                let data = try JSONEncoder().encode(SystemUPSReader().readUPS())
                FileHandle.standardOutput.write(data)
                return
            }
            if CommandLine.arguments.contains("--read-hid") {
                let reader = HIDUPSReader()
                reader.start()
                let snapshot = reader.readSnapshot()
                reader.stop()
                FileHandle.standardOutput.write(try JSONEncoder().encode(snapshot))
                return
            }
        } catch {
            exit(1)
        }
        APCUPSMonitorApp.main()
    }
}

struct APCUPSMonitorApp: App {
    @StateObject private var model = UPSMonitorModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
                .frame(width: 320)
        } label: {
            Label(model.menuTitle, systemImage: model.isOnBattery ? "battery.75percent" : "bolt.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
