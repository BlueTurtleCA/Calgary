//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// CommandRunner.swift
//

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

/// A command and its arguments, so a pipeline can declare one command per
/// platform:
///
/// ```swift
/// site.executeCommand(
///     CommandInvocation("npx", arguments: ["--yes", "@tailwindcss/cli", "-i", "input.css", "-o", "output.css"]),
///     windows: CommandInvocation("npx.cmd", arguments: ["--yes", "@tailwindcss/cli", "-i", "input.css", "-o", "output.css"]),
///     input: "input.css",
///     output: "output.css"
/// )
/// ```
public struct CommandInvocation: Sendable, Equatable {
    /// The executable to run.
    public let command: String

    /// Arguments passed to the command.
    public let arguments: [String]

    public init(_ command: String, arguments: [String] = []) {
        self.command = command
        self.arguments = arguments
    }
}

/// Abstraction over running external commands.
public protocol CommandRunner: Sendable {
    /// Runs `command` with `arguments` in `workingDirectory`.
    ///
    /// - Throws: `BuildError.commandNotFound` if the command cannot be
    ///   resolved, or `BuildError.commandFailed` if it cannot be started.
    func run(command: String, arguments: [String], workingDirectory: URL) throws -> CommandResult
}

/// Runs commands with `Process`, resolving the command from the process's
/// `PATH` and from `additionalSearchDirectories`.
public struct ProcessCommandRunner: CommandRunner {
    /// The environment the child process runs with.
    public var environment: [String: String]

    /// Directories searched after the environment's `PATH`, for commands the
    /// host environment does not expose.
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

        // The exit status is only meaningful when the process exited
        // normally; a signal death reports the signal that killed it.
        // Windows is exempt: `Process` there flags certain legitimate exit
        // codes (such as 3) as an uncaught signal, and its status is set in
        // both cases.
        #if !os(Windows)
        guard process.terminationReason == .exit else {
            throw BuildError.commandFailed(
                command: command,
                exitCode: process.terminationStatus,
                output: "The command was terminated by a signal."
            )
        }
        #endif

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: try Data(contentsOf: stdoutFile),
            standardError: try Data(contentsOf: stderrFile)
        )
    }

    /// The common install locations for Node.js and other command-line
    /// tools, used as the default for `additionalSearchDirectories`.
    public static func defaultAdditionalSearchDirectories() -> [URL] {
        #if os(Windows)
        func value(_ name: String) -> String? {
            ProcessInfo.processInfo.environment.first {
                $0.key.caseInsensitiveCompare(name) == .orderedSame
            }?.value
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories: [URL] = []
        if let programFiles = value("ProgramFiles") {
            directories.append(URL(fileURLWithPath: programFiles).appendingPathComponent("nodejs"))
        }
        if let localAppData = value("LOCALAPPDATA") {
            let base = URL(fileURLWithPath: localAppData)
            // The per-user Node.js installer and winget's link directory.
            directories.append(base.appendingPathComponent("Programs").appendingPathComponent("nodejs"))
            directories.append(
                base.appendingPathComponent("Microsoft").appendingPathComponent("WinGet").appendingPathComponent("Links")
            )
        }
        if let appData = value("APPDATA") {
            // npm's global install location, where npx and friends live.
            directories.append(URL(fileURLWithPath: appData).appendingPathComponent("npm"))
        }
        directories.append(home.appendingPathComponent(".volta").appendingPathComponent("bin"))
        directories.append(home.appendingPathComponent("scoop").appendingPathComponent("shims"))
        if let nvmHome = value("NVM_HOME") {
            // nvm-windows installs Node here.
            directories.append(URL(fileURLWithPath: nvmHome))
        }
        return directories
        #else
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment

        var directories: [URL] = [
            // Homebrew
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            // Local user installs
            home.appendingPathComponent(".local/bin"),
            // nvm
            home.appendingPathComponent(".nvm").appendingPathComponent("versions"),
            // Volta
            home.appendingPathComponent(".volta/bin"),
            // asdf
            home.appendingPathComponent(".asdf/shims"),
            // mise
            home.appendingPathComponent(".mise/shims"),
        ]

        // nvm installs Node under versions/<version>/bin; walk the
        // version folders.
        let nvmVersions = home.appendingPathComponent(".nvm/versions/node")
        if let versionDirectories = try? fileManager.contentsOfDirectory(at: nvmVersions, includingPropertiesForKeys: nil) {
            directories.append(contentsOf: versionDirectories.map { $0.appendingPathComponent("bin") })
        }

        // Honor NVM_BIN and NVM_DIR when set.
        if let nvmBin = environment["NVM_BIN"] {
            directories.append(URL(fileURLWithPath: nvmBin))
        }
        if let nvmDir = environment["NVM_DIR"] {
            let versions = URL(fileURLWithPath: nvmDir)
                .appendingPathComponent("versions")
                .appendingPathComponent("node")
            let versionDirectories = (try? fileManager.contentsOfDirectory(
                at: versions,
                includingPropertiesForKeys: nil
            )) ?? []
            directories.append(contentsOf: versionDirectories.map { $0.appendingPathComponent("bin") })
        }

        return directories
        #endif
    }

    /// Resolves `command` to an executable file.
    ///
    /// A command that is a path (contains a path separator) is used as is.
    /// Otherwise each directory in the process's `PATH`, followed by
    /// `additionalSearchDirectories`, is searched for a file with the
    /// command's name.
    private func resolveExecutable(_ command: String) throws -> URL {
        let fileManager = FileManager.default

        if Self.looksLikePath(command) {
            let url = URL(fileURLWithPath: command)
            guard Self.isRunnable(fileManager, at: url) else {
                throw BuildError.commandNotFound(command: command)
            }
            return url
        }

        let pathDirectories = Self.pathDirectories(
            in: ProcessInfo.processInfo.environment
        )
        for directory in pathDirectories + additionalSearchDirectories {
            for candidate in Self.candidates(for: command, in: directory) {
                if Self.isRunnable(fileManager, at: candidate) {
                    return candidate
                }
            }
        }

        throw BuildError.commandNotFound(command: command)
    }

    /// Whether `command` names a file by path rather than by name.
    private static func looksLikePath(_ command: String) -> Bool {
        #if os(Windows)
        return command.contains("/") || command.contains("\\")
        #else
        return command.contains("/")
        #endif
    }

    /// The file names to look for `command` in a directory.
    ///
    /// On Windows the name is also tried with each `PATHEXT` extension, so a
    /// Node.js install's `npx.cmd` is found by the name `npx`.
    private static func candidates(for command: String, in directory: URL) -> [URL] {
        #if os(Windows)
        let names = [command] + pathExtensions.map { command + $0 }
        #else
        let names = [command]
        #endif
        return names.map { directory.appendingPathComponent($0) }
    }

    /// Whether the file at `url` can be run as a command.
    private static func isRunnable(_ fileManager: FileManager, at url: URL) -> Bool {
        #if os(Windows)
        // Windows has no executable bit: a file the system knows how to run
        // (.exe, .cmd, .bat, …) is a regular file, so existence is the test.
        return fileManager.fileExists(atPath: url.path)
        #else
        return fileManager.isExecutableFile(atPath: url.path)
        #endif
    }

    /// The directories named by the `PATH` in `environment`.
    private static func pathDirectories(in environment: [String: String]) -> [URL] {
        #if os(Windows)
        // Environment names are case-insensitive and are usually spelled
        // `Path`.
        let path = environment.first { $0.key.caseInsensitiveCompare("PATH") == .orderedSame }?.value ?? ""
        return path.split(separator: ";").map { URL(fileURLWithPath: String($0)) }
        #else
        return environment["PATH"]?
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)) } ?? []
        #endif
    }

    /// The environment the child process runs with.
    ///
    /// The resolved executable's directory is prepended to the `PATH` so the
    /// command can find sibling binaries — for example, `npx` invokes
    /// `node`, which sits next to it.
    private func childEnvironment(for executableURL: URL) -> [String: String] {
        var environment = self.environment
        let executableDirectory = executableURL.deletingLastPathComponent().path
        #if os(Windows)
        // Environment names are case-insensitive and are usually spelled
        // `Path`.
        let pathKey = environment.first { $0.key.caseInsensitiveCompare("PATH") == .orderedSame }?.key ?? "PATH"
        let path = environment[pathKey] ?? ""
        if path.components(separatedBy: ";").contains(executableDirectory) != true {
            environment[pathKey] = path.isEmpty ? executableDirectory : executableDirectory + ";" + path
        }
        #else
        if environment["PATH"]?.components(separatedBy: ":").contains(executableDirectory) != true {
            let path = environment["PATH"] ?? ""
            environment["PATH"] = path.isEmpty ? executableDirectory : executableDirectory + ":" + path
        }
        #endif
        return environment
    }

    #if os(Windows)
    /// The executable extensions appended to command names, from the
    /// environment's `PATHEXT` (default `.COM;.EXE;.BAT;.CMD`).
    private static let pathExtensions: [String] = {
        let value = ProcessInfo.processInfo.environment.first {
            $0.key.caseInsensitiveCompare("PATHEXT") == .orderedSame
        }?.value ?? ".COM;.EXE;.BAT;.CMD"
        return value.split(separator: ";").map(String.init)
    }()
    #endif

    /// Creates an empty temporary file to capture a process's output.
    private func makeTemporaryFile(fileManager: FileManager) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calgary-command-output-\(UUID().uuidString)")
        fileManager.createFile(atPath: url.path, contents: nil)
        return url
    }
}
