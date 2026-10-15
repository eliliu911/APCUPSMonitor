import Foundation
import Darwin

@main
struct MemoryStress {
    @MainActor
    static func main() async {
        let reader = SnapshotProcess()
        let cycles = Int(CommandLine.arguments.dropFirst().first ?? "2000") ?? 2000
        func footprint() -> UInt64 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
                }
            }
            precondition(result == 0)
            return info.ri_phys_footprint
        }
        var warm: UInt64 = 0
        for i in 1...cycles {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                reader.read(executable: URL(fileURLWithPath: "/usr/bin/printf"), argument: "{}") { result in
                    precondition((try? result.get()) == Data("{}".utf8))
                    continuation.resume()
                }
            }
            if i == 100 { warm = footprint() }
            if i % 500 == 0 { print("cycles=\(i) footprintMiB=\(Double(footprint()) / 1048576)") }
        }
        print("growthAfterWarmupMiB=\(Double(Int64(footprint()) - Int64(warm)) / 1048576)")
    }
}
