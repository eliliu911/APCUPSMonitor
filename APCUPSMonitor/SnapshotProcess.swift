import Foundation
import Darwin

/// All lifecycle state is confined to the main actor. Each channel permits only
/// one child, including while a timed-out child is being reaped.
@MainActor
final class SnapshotProcess {
    enum ReadError: LocalizedError {
        case timeout, failed(Int32), invalidOutput
        var errorDescription: String? {
            switch self {
            case .timeout: return "Read timed out; retrying automatically"
            case .failed(let code): return "Reader exited (\(code)); retrying automatically"
            case .invalidOutput: return "Invalid reader output; retrying automatically"
            }
        }
    }

    private var process: Process?
    private var timeoutTask: Task<Void, Never>?
    private var outputURL: URL?
    private var outputHandle: FileHandle?
    private var completion: ((Result<Data, Error>) -> Void)?
    var isRunning: Bool { process != nil }

    func read(executable: URL, argument: String, timeout: TimeInterval = 5,
              completion: @escaping (Result<Data, Error>) -> Void) {
        guard process == nil else { return }
        let child = Process()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apc-snapshot-\(UUID().uuidString).json")
        do {
            // A file avoids filling a pipe if a device exposes many HID elements.
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                attributes: [.posixPermissions: 0o600]) else {
                throw ReadError.invalidOutput
            }
            let handle = try FileHandle(forWritingTo: url)
            outputURL = url
            outputHandle = handle
            self.completion = completion
            child.executableURL = executable
            child.arguments = [argument]
            child.standardOutput = handle
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] child in
                Task { @MainActor in self?.finished(child) }
            }
            process = child
            try child.run()
            timeoutTask = Task { [weak self, weak child] in
                do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
                catch { return }
                guard let self, let child, self.process === child else { return }
                if child.isRunning && child.processIdentifier > 0 {
                    kill(child.processIdentifier, SIGKILL)
                    let callback = self.completion
                    self.completion = nil
                    callback?(.failure(ReadError.timeout))
                }
            }
        } catch {
            process = nil
            self.completion = nil
            cleanOutput()
            try? FileManager.default.removeItem(at: url)
            completion(.failure(error))
        }
    }

    private func finished(_ child: Process) {
        guard process === child else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        let callback = completion
        completion = nil
        let result: Result<Data, Error>
        if child.terminationStatus != 0 {
            result = .failure(ReadError.failed(child.terminationStatus))
        } else if let url = outputURL, let data = try? Data(contentsOf: url), !data.isEmpty {
            result = .success(data)
        } else {
            result = .failure(ReadError.invalidOutput)
        }
        process = nil
        cleanOutput()
        callback?(result)
    }

    func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        completion = nil
        // Keep the child recorded until terminationHandler reaps it. Repeated
        // refresh/wake requests must never spawn an unbounded set of readers.
        if let process, process.isRunning, process.processIdentifier > 0 { kill(process.processIdentifier, SIGKILL) }
    }

    private func cleanOutput() {
        try? outputHandle?.close()
        outputHandle = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
    }

    deinit {
        timeoutTask?.cancel()
        if let process, process.isRunning, process.processIdentifier > 0 { kill(process.processIdentifier, SIGKILL) }
        try? outputHandle?.close()
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    }
}
