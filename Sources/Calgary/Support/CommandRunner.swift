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
    ///     `PATH` and the runner's additional search directories (for
    ///     example, `"npx"`) or a path to an executable.
    ///   - arguments: Arguments passed to the command.
    ///   - workingDirectory: The directory the command runs in.
    /// - Returns: The command's exit status and captured output.
    func run(command: String, arguments: [String], workingDirectory: URL) throws -> CommandResult
}

/// A `CommandRunner` that runs real processes via `Process`.
///
/// A command given by name is resolved against `PATH` first, then against
/// `additionalSearchDirectories`. The resolved executable's directory is
/// prepended to the child's `PATH`, so the command can find sibling
/// binaries — for example, `npx` invokes `node`, which sits next to it.
public struct ProcessCommandRunner: CommandRunner {
    /// The environment the command runs with.
    ///
    /// Defaults to the current process's environment.
    public var environment: [String: String]

    /// Directories searched when a command is not found in `PATH`.
    ///
    /// Defaults to the common install locations for Node.js and other
    /// command-line tools (Homebrew, nvm, Volta, ...), which are missing
    /// from the minimal `PATH` that Xcode gives to processes launched with
    /// its run button.
    public var additionalSearchDirectories: [URL]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [URL] = ProcessCommandRunner.defaultAdditionalSearchDirectories()
    ) {
        self.environment = environment
        self.additionalSearchDirectories = additionalSearchDirectories
    }

    public func run(command: String, arguments: [String], workingDirectory: URL) throws -> CommandResult {
        let executableURL = try resolveExecutable(command)
        let childEnvironment = childEnvironment(for: executableURL)

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
        process.environment = childEnvironment
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

        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]
            .map { $0.split(separator: ":").map { URL(fileURLWithPath: String($0)) } }
            ?? []

        for directory in pathDirectories + additionalSearchDirectories {
            let candidate = directory.appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw BuildError.commandNotFound(command: command)
    }

    /// The environment the child process runs with.
    ///
    /// The resolved executable's directory is prepended to `PATH` so the
    /// command can find sibling binaries — for example, `npx` invokes
    /// `node`, which sits next to it.
    private func childEnvironment(for executableURL: URL) -> [String: String] {
        var environment = environment
        let executableDirectory = executableURL.deletingLastPathComponent().path
        if environment["PATH"]?.components(separatedBy: ":").contains(executableDirectory) != true {
            let path = environment["PATH"] ?? ""
            environment["PATH"] = path.isEmpty ? executableDirectory : executableDirectory + ":" + path
        }
        return environment
    }

    /// The common install locations for Node.js and other command-line
    /// tools, used as the default for `additionalSearchDirectories`.
    public static func defaultAdditionalSearchDirectories() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        var directories: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin"), // Homebrew on Apple Silicon
            URL(fileURLWithPath: "/usr/local/bin"),    // Homebrew on Intel, official Node installer
            home.appendingPathComponent(".local/bin"),
            home.appendingPathComponent(".volta/bin"),
            home.appendingPathComponent(".asdf/shims"),
            home.appendingPathComponent(".local/share/mise/shims"),
        ]

        // nvm keeps each installed Node version under
        // ~/.nvm/versions/node/<version>/bin, newest first.
        let nvmVersions = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fileManager.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil
        ) {
            directories.append(contentsOf: versions
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .map { $0.appendingPathComponent("bin") })
        }

        return directories
    }

    private func makeTemporaryFile(fileManager: FileManager) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("calgary-command-\(UUID().uuidString)")
        fileManager.createFile(atPath: url.path, contents: Data())
        return url
    }
}
