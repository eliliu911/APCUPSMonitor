import SwiftUI
import Darwin

@main
enum APCUPSMonitorEntry {
    // Retained for the GUI's lifetime; CLOEXEC prevents reader children from
    // holding the lock after the parent quits. Reader modes bypass the lock.
    private static var instanceLock: Int32 = -1

    private static func claimInstance() -> Bool {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("APCUPSMonitor", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("instance.lock").path
            let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { return false }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                close(fd)
                return false
            }
            instanceLock = fd
            return true
        } catch {
            return false
        }
    }

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
        guard claimInstance() else { return }
        APCUPSMonitorApp.main()
    }
}

struct APCUPSMonitorApp: App {
    @NSApplicationDelegateAdaptor(StatusItemController.self) private var controller

    var body: some Scene {
        Settings { EmptyView() }
    }
}
