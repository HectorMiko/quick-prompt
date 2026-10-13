import Foundation
import os

/// Calls Claude through the Claude Code CLI, using the user's Claude subscription.
/// The text goes through stdin, never as an argument.
public struct ClaudeCLIProvider: LLMProvider {
    public static let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/claude").path

    private let executablePath: String
    private let logger = Logger(subsystem: CoreLog.subsystem, category: "cli")

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    /// Arguments that keep the user's Claude Code setup (CLAUDE.md, plugins, hooks, MCP, tools) out of the call.
    static func arguments(for request: LLMRequest) -> [String] {
        var arguments = [
            "-p",
            "--model", request.model,
            "--system-prompt", request.system,
            "--tools", "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--setting-sources", "",
        ]
        if let effort = request.effort {
            arguments += ["--effort", effort.rawValue]
        }
        return arguments
    }

    public func complete(_ request: LLMRequest) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LLMError.cliNotFound(path: executablePath)
        }
        logger.info("""
            claude -p model=\(request.model, privacy: .public) \
            effort=\(request.effort?.rawValue ?? "none", privacy: .public) \
            timeout=\(Int(request.timeout))s input length=\(request.user.count)
            """)

        let run = CLIRun(executablePath: executablePath, arguments: Self.arguments(for: request), input: request.user)
        let start = Date()
        let result: CLIRun.Result
        do {
            result = try await withTimeout(request.timeout) {
                try await withTaskCancellationHandler {
                    try await run.start()
                } onCancel: {
                    run.terminate()
                }
            }
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch {
            logger.error("CLI failure: \(String(describing: error), privacy: .public)")
            throw error
        }
        let elapsed = Date().timeIntervalSince(start)
        logger.info("""
            exit=\(result.exitCode) in \(elapsed, format: .fixed(precision: 2))s, \
            stdout length=\(result.stdout.count), stderr length=\(result.stderr.count)
            """)

        guard result.exitCode == 0 else {
            throw LLMError.cliFailed(exitCode: result.exitCode, message: Self.errorLine(result))
        }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }

    /// First line of the CLI error output, shortened. Claude Code prints its errors on stdout.
    static func errorLine(_ result: CLIRun.Result) -> String? {
        let output = result.stderr.isEmpty ? result.stdout : result.stderr
        guard let line = output.split(whereSeparator: \.isNewline).first else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.count > 160 ? String(text.prefix(160)) + "…" : text
    }
}

/// One CLI process. Blocking pipe I/O runs on background queues.
final class CLIRun: @unchecked Sendable {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private let process = Process()
    private let input: Data
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    // Written on a background queue, read after `group.wait()`.
    private var stderrData = Data()

    init(executablePath: String, arguments: [String], input: String) {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Empty working directory: no project CLAUDE.md or settings are picked up.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quick-prompt-cli", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        process.currentDirectoryURL = directory
        self.input = Data(input.utf8)
    }

    func start() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: LLMError.cliFailed(exitCode: -1, message: "Could not launch Claude Code"))
                    return
                }
                let group = DispatchGroup()
                DispatchQueue.global().async(group: group) { [self] in
                    stdinPipe.fileHandleForWriting.write(input)
                    try? stdinPipe.fileHandleForWriting.close()
                }
                DispatchQueue.global().async(group: group) { [self] in
                    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                }
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: Result(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: stdout, as: UTF8.self),
                    stderr: String(decoding: stderrData, as: UTF8.self)
                ))
            }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
