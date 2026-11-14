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
    /// The executable to run.
    let command: String

    /// Arguments passed to the command.
    let arguments: [String]

    /// The file the command reads, relative to the site's root.
    let input: String?

    /// The file the command writes, relative to the site's root.
    let output: String?

    var name: String {
        "Run '\(([command] + arguments).joined(separator: " "))'"
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
                command: command,
                arguments: arguments,
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
            throw BuildError.commandFailed(command: command, exitCode: result.exitCode, output: output)
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
