import Foundation

struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }
    var combinedOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum ADBError: LocalizedError {
    case notFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Could not find the adb tool. Install it with:  brew install android-platform-tools"
        case .commandFailed(let message):
            return message
        }
    }
}

/// Thin wrapper around the `adb` command-line tool.
struct ADB {
    let path: String

    /// Locations adb is commonly installed at. A GUI app launched from Finder
    /// does not inherit the shell PATH, so we probe known paths directly.
    static func locate() -> ADB? {
        let candidates = [
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/opt/homebrew/Caskroom/android-platform-tools/latest/platform-tools/adb",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return ADB(path: candidate)
        }
        return nil
    }

    @discardableResult
    func run(_ arguments: [String]) async throws -> CommandResult {
        let exePath = path
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: exePath)
                process.arguments = arguments

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Drain both pipes off-thread so neither can fill up and stall the process.
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                process.waitUntilExit()
                group.wait()

                continuation.resume(returning: CommandResult(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                ))
            }
        }
    }

    /// Runs a command and throws if adb reports failure.
    @discardableResult
    func runChecked(_ arguments: [String]) async throws -> CommandResult {
        let result = try await run(arguments)
        guard result.succeeded else {
            throw ADBError.commandFailed(result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    /// Quotes a device-side path for the phone's shell.
    static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
