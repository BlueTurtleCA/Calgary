import Foundation

/// The result of running a command.
public struct CommandResult: Sendable, Equatable {
    /// The process's exit status. Zero means success.
    public let exitCode: Int32

    /// Everything the process wrote to standard output.
    public let standardOutput: Data

    /// Everything the process wrote to standard error.
    public let standardError: Data

    public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Abstraction over running external commands.
///
/// `Site` runs commands through a `CommandRunner`, so builds can run real
/// processes (the default, `ProcessCommandRunner`) or a scripted stand-in in
/// tests.
public protocol CommandRunner: Sendable {
    /// Runs `command` with `arguments` in `workingDirectory`.
    ///
    /// - Parameters:
    ///   - command: The executable to run. Either a name resolved against
    ///     `PATH` (for example, `"npx"`) or a path to an executable.
    ///   - arguments: Arguments passed to the command.
    ///   - workingDirectory: The directory the command runs in.
    /// - Returns: The command's exit status and captured output.
    func run(command: String, arguments: [String], workingDirectory: URL) throws -> CommandResult
}

/// A `CommandRunner` that runs real processes via `Process`.
public struct ProcessCommandRunner: CommandRunner {
    /// The environment the command runs with.
    ///
    /// Defaults to the current process's environment.
    public var environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func run(command: String, arguments: [String], workingDirectory: URL) throws -> CommandResult {
        let executableURL = try resolveExecutable(command)

        // Capture the command's output in temporary files rather than pipes:
        // a child that writes more than a pipe buffer cannot deadlock the
        // wait below.
        let fileManager = FileManager.default
        let stdoutFile = try makeTemporaryFile(fileManager: fileManager)
        let stderrFile = try makeTemporaryFile(fileManager: fileManager)
        defer {
            try? fileManager.removeItem(at: stdoutFile)
            try? fileManager.removeItem(at: stderrFile)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = try FileHandle(forWritingTo: stdoutFile)
        process.standardError = try FileHandle(forWritingTo: stderrFile)

        try process.run()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: try Data(contentsOf: stdoutFile),
            standardError: try Data(contentsOf: stderrFile)
        )
    }

    private func resolveExecutable(_ command: String) throws -> URL {
        let fileManager = FileManager.default

        if command.contains("/") {
            let url = URL(fileURLWithPath: command)
            guard fileManager.isExecutableFile(atPath: url.path) else {
                throw BuildError.commandNotFound(command: command)
            }
            return url
        }

        guard let path = ProcessInfo.processInfo.environment["PATH"] else {
            throw BuildError.commandNotFound(command: command)
        }
        let searchDirectories = path
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)) }

        for directory in searchDirectories {
            let candidate = directory.appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw BuildError.commandNotFound(command: command)
    }

    private func makeTemporaryFile(fileManager: FileManager) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("calgary-command-\(UUID().uuidString)")
        fileManager.createFile(atPath: url.path, contents: Data())
        return url
    }
}
