import Foundation

struct ProcessCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    var environment: [String: String] = [:]
    var timeout: TimeInterval?

    static func system(_ path: String, _ arguments: [String] = [], timeout: TimeInterval? = nil) -> ProcessCommand {
        ProcessCommand(executableURL: URL(fileURLWithPath: path), arguments: arguments, timeout: timeout)
    }

    var displayString: String {
        ([executableURL.path] + arguments).map { $0.shellSingleQuoted }.joined(separator: " ")
    }

    nonisolated static func == (lhs: ProcessCommand, rhs: ProcessCommand) -> Bool {
        lhs.executableURL == rhs.executableURL &&
        lhs.arguments == rhs.arguments &&
        lhs.environment == rhs.environment &&
        lhs.timeout == rhs.timeout
    }
}

struct ProcessResult: Equatable, Sendable {
    let command: ProcessCommand
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    var combinedOutput: String {
        [standardOutput, standardError].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    nonisolated static func == (lhs: ProcessResult, rhs: ProcessResult) -> Bool {
        lhs.command == rhs.command &&
        lhs.terminationStatus == rhs.terminationStatus &&
        lhs.standardOutput == rhs.standardOutput &&
        lhs.standardError == rhs.standardError
    }
}

enum ProcessRunnerError: LocalizedError, Equatable {
    case nonZeroExit(ProcessResult)
    case timedOut(ProcessCommand)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let result):
            let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return "\(result.command.displayString) exited with status \(result.terminationStatus)."
            }
            return "\(result.command.displayString) exited with status \(result.terminationStatus):\n\(output)"
        case .timedOut(let command):
            return "\(command.displayString) timed out."
        }
    }
}

protocol ProcessRunning: Sendable {
    @discardableResult
    func run(_ command: ProcessCommand, onOutput: @escaping @Sendable (String) -> Void) async throws -> ProcessResult
}

final class ProcessRunner: ProcessRunning {
    nonisolated init() {}

    @discardableResult
    func run(_ command: ProcessCommand, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdout = OutputBuffer()
        let stderr = OutputBuffer()
        let runningProcess = RunningProcess(process)
        let timedOut = AtomicFlag()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            stdout.append(text)
            onOutput(text)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            stderr.append(text)
            onOutput(text)
        }

        if let timeout = command.timeout {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                timedOut.set()
                runningProcess.terminate()
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    if !remainingStdout.isEmpty {
                        stdout.append(String(decoding: remainingStdout, as: UTF8.self))
                    }

                    let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    if !remainingStderr.isEmpty {
                        stderr.append(String(decoding: remainingStderr, as: UTF8.self))
                    }

                    let result = ProcessResult(
                        command: command,
                        terminationStatus: process.terminationStatus,
                        standardOutput: stdout.content,
                        standardError: stderr.content
                    )

                    if timedOut.value {
                        continuation.resume(throwing: ProcessRunnerError.timedOut(command))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: ProcessRunnerError.nonZeroExit(result))
                    }
                }

                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            runningProcess.terminate()
        }
    }
}

private final class RunningProcess: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()

    init(_ process: Process) {
        self.process = process
    }

    nonisolated func terminate() {
        lock.withLock {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    nonisolated(unsafe) private var storage = ""
    private let lock = NSLock()

    nonisolated func append(_ text: String) {
        lock.withLock {
            storage.append(text)
        }
    }

    nonisolated var content: String {
        lock.withLock { storage }
    }
}

private final class AtomicFlag: @unchecked Sendable {
    nonisolated(unsafe) private var storage = false
    private let lock = NSLock()

    nonisolated func set() {
        lock.withLock {
            storage = true
        }
    }

    nonisolated var value: Bool {
        lock.withLock { storage }
    }
}
