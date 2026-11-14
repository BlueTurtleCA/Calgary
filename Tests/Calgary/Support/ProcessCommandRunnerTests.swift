//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// ProcessCommandRunnerTests.swift
//

import Foundation
import Testing
@testable import Calgary

/// Tests for the real `ProcessCommandRunner`.
///
/// These run small, side-effect-free system commands (`echo`, `sh`, `pwd`)
/// and temporary shell scripts, so the production path — PATH resolution,
/// output capture, working directory — is covered without touching the
/// project's files.
@Suite("ProcessCommandRunner")
struct ProcessCommandRunnerTests {
    private let runner = ProcessCommandRunner()

    @Test("Resolves the executable from PATH and captures its output")
    func resolvesFromPathAndCapturesOutput() throws {
        let result = try runner.run(
            command: "echo",
            arguments: ["hello"],
            workingDirectory: URL(fileURLWithPath: "/")
        )

        #expect(result.exitCode == 0)
        #expect(String(data: result.standardOutput, encoding: .utf8) == "hello\n")
    }

    @Test("Captures the exit code and standard error")
    func capturesExitCodeAndStandardError() throws {
        let result = try runner.run(
            command: "sh",
            arguments: ["-c", "echo oops 1>&2; exit 3"],
            workingDirectory: URL(fileURLWithPath: "/")
        )

        #expect(result.exitCode == 3)
        #expect(String(data: result.standardError, encoding: .utf8) == "oops\n")
    }

    @Test("Runs the command in the given working directory")
    func runsInWorkingDirectory() throws {
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let result = try runner.run(
            command: "pwd",
            arguments: [],
            workingDirectory: workingDirectory
        )

        #expect(result.exitCode == 0)
        #expect(String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == workingDirectory.path)
    }

    @Test("Throws when the executable cannot be found")
    func throwsWhenExecutableIsMissing() throws {
        #expect(throws: BuildError.commandNotFound(command: "calgary-not-a-real-command")) {
            try runner.run(
                command: "calgary-not-a-real-command",
                arguments: [],
                workingDirectory: URL(fileURLWithPath: "/")
            )
        }
    }

    @Test("Falls back to the additional search directories when the command is not on PATH")
    func resolvesFromAdditionalSearchDirectories() throws {
        let directory = try makeScriptDirectory(named: "calgary-fake-command", body: "echo fake")
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = ProcessCommandRunner(
            environment: ["PATH": "/nonexistent"],
            additionalSearchDirectories: [directory]
        )
        let result = try runner.run(
            command: "calgary-fake-command",
            arguments: [],
            workingDirectory: URL(fileURLWithPath: "/")
        )

        #expect(result.exitCode == 0)
        #expect(String(data: result.standardOutput, encoding: .utf8) == "fake\n")
    }

    @Test("Prepends the resolved executable's directory to the child's PATH")
    func prependsExecutableDirectoryToChildPath() throws {
        let directory = try makeScriptDirectory(named: "calgary-print-path", body: "echo $PATH")
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = ProcessCommandRunner(
            environment: ["PATH": "/nonexistent"],
            additionalSearchDirectories: [directory]
        )
        let result = try runner.run(
            command: "calgary-print-path",
            arguments: [],
            workingDirectory: URL(fileURLWithPath: "/")
        )

        let path = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #expect(path.components(separatedBy: ":").first == directory.path)
    }

    /// Writes a shell script named `name` into a fresh temporary directory
    /// and returns the directory, so tests can resolve commands that are
    /// not on the test process's `PATH`.
    private func makeScriptDirectory(named name: String, body: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("calgary-runner-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return directory
    }
}
