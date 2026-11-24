//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// ExecuteCommandStep.swift
//

import Foundation

/// A build step that runs an external command.
///
/// The command runs with the site's root as its working directory, so
/// relative paths in its arguments resolve against the project. The step's
/// `input` and `output` declare the files the command reads and writes; both
/// are validated so a broken command fails the build with a clear error
/// instead of producing a half-built site:
///
/// ```swift
/// site.executeCommand(
///     "npx",
///     arguments: ["tailwindcss", "-i", "assets/css/input.css", "-o", "build/css/site.css"],
///     input: "assets/css/input.css",
///     output: "build/css/site.css"
/// )
/// ```
struct ExecuteCommandStep: BuildStep {
    /// The command to run when the platform has no override.
    let fallback: CommandInvocation

    /// The command to run on each platform when it differs from `fallback`.
    let windows: CommandInvocation?
    let macos: CommandInvocation?
    let linux: CommandInvocation?

    /// The file the command reads, relative to the site's root.
    let input: String?

    /// The file the command writes, relative to the site's root.
    let output: String?

    /// The platform the command is selected for.
    ///
    /// Defaults to the platform the build runs on; tests force a value to
    /// exercise the selection without a specific host.
    let platform: Platform

    init(
        fallback: CommandInvocation,
        windows: CommandInvocation? = nil,
        macos: CommandInvocation? = nil,
        linux: CommandInvocation? = nil,
        input: String? = nil,
        output: String? = nil,
        platform: Platform = .current
    ) {
        self.fallback = fallback
        self.windows = windows
        self.macos = macos
        self.linux = linux
        self.input = input
        self.output = output
        self.platform = platform
    }

    /// The command and arguments selected for the platform: the platform's
    /// override when one is declared, otherwise `fallback`.
    var invocation: CommandInvocation {
        switch platform {
        case .windows:
            return windows ?? fallback
        case .macOS:
            return macos ?? fallback
        case .linux:
            return linux ?? fallback
        }
    }

    var name: String {
        "Run '\(([invocation.command] + invocation.arguments).joined(separator: " "))'"
    }

    func run(site: Site) throws {
        if let input {
            let inputURL = site.root.appendingPathComponent(input)
            guard site.fileSystem.fileExists(atPath: inputURL.path) else {
                throw BuildError.missingPath(inputURL.path)
            }
        }

        let result: CommandResult
        do {
            result = try site.commandRunner.run(
                command: invocation.command,
                arguments: invocation.arguments,
                workingDirectory: site.root
            )
        } catch let error as BuildError {
            throw error
        }

        guard result.exitCode == 0 else {
            let stderr = String(data: result.standardError, encoding: .utf8) ?? ""
            let stdout = String(data: result.standardOutput, encoding: .utf8) ?? ""
            let output: String
            if !stderr.isEmpty {
                output = stderr
            } else if !stdout.isEmpty {
                output = stdout
            } else {
                output = "The command exited with status \(result.exitCode)."
            }
            throw BuildError.commandFailed(
                command: invocation.command,
                exitCode: result.exitCode,
                output: output
            )
        }

        if let output {
            let outputURL = site.root.appendingPathComponent(output)
            guard site.fileSystem.fileExists(atPath: outputURL.path) else {
                throw BuildError.missingPath(outputURL.path)
            }
            guard !site.fileSystem.isDirectory(atPath: outputURL.path) else {
                throw BuildError.unexpectedPathType(path: outputURL.path, expected: "file")
            }
        }
    }
}
