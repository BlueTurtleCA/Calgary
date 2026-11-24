//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// ProcessCommandRunnerWindowsTests.swift
//

#if os(Windows)
import Foundation
import Testing
@testable import Calgary

/// Tests for the real `ProcessCommandRunner` on Windows.
///
/// These run `cmd`, the Windows command interpreter, and temporary `.cmd`
/// shims, so the production path — PATH resolution, `PATHEXT` name lookup,
/// output capture, working directory — is covered without touching the
/// project's files.
@Suite("ProcessCommandRunner (Windows)")
struct ProcessCommandRunnerWindowsTests {
    private let runner = ProcessCommandRunner()

    @Test("Resolves the executable from PATH and captures its output")
    func resolvesFromPathAndCapturesOutput() throws {
        let result = try runner.run(
            command: "cmd",
            arguments: ["/c", "echo hello"],
            workingDirectory: URL(fileURLWithPath: "C:\\")
        )

        #expect(result.exitCode == 0)
        #expect(String(data: result.standardOutput, encoding: .utf8) == "hello\r\n")
    }

    @Test("Captures the exit code and standard error")
    func capturesExitCodeAndStandardError() throws {
        let result = try runner.run(
            command: "cmd",
            arguments: ["/c", "echo oops 1>&2 & exit 3"],
            workingDirectory: URL(fileURLWithPath: "C:\\")
        )

        #expect(result.exitCode == 3)
        #expect(String(data: result.standardError, encoding: .utf8) == "oops\r\n")
    }

    @Test("Runs the command in the given working directory")
    func runsInWorkingDirectory() throws {
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let result = try runner.run(
            command: "cmd",
            arguments: ["/c", "cd"],
            workingDirectory: workingDirectory
        )

        #expect(result.exitCode == 0)
        let path = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #expect(path.lowercased() == workingDirectory.path.lowercased())
    }

    @Test("Throws when the executable cannot be found")
    func throwsWhenExecutableIsMissing() throws {
        #expect(throws: BuildError.commandNotFound(command: "calgary-not-a-real-command")) {
            try runner.run(
                command: "calgary-not-a-real-command",
                arguments: [],
                workingDirectory: URL(fileURLWithPath: "C:\\")
            )
        }
    }

    @Test("Falls back to the additional search directories for a .cmd shim")
    func resolvesCmdShimFromAdditionalSearchDirectories() throws {
        let directory = try makeShimDirectory(named: "calgary-fake-command", body: "@echo fake")
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = ProcessCommandRunner(
            environment: ["PATH": "C:\\nonexistent"],
            additionalSearchDirectories: [directory]
        )
        let result = try runner.run(
            command: "calgary-fake-command",
            arguments: [],
            workingDirectory: URL(fileURLWithPath: "C:\\")
        )

        #expect(result.exitCode == 0)
        #expect(String(data: result.standardOutput, encoding: .utf8) == "fake\r\n")
    }

    @Test("Prepends the resolved executable's directory to the child's PATH")
    func prependsExecutableDirectoryToChildPath() throws {
        let directory = try makeShimDirectory(named: "calgary-print-path", body: "@echo %PATH%")
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = ProcessCommandRunner(
            environment: ["Path": "C:\\nonexistent"],
            additionalSearchDirectories: [directory]
        )
        let result = try runner.run(
            command: "calgary-print-path",
            arguments: [],
            workingDirectory: URL(fileURLWithPath: "C:\\")
        )

        let path = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #expect(path.components(separatedBy: ";").first?.lowercased() == directory.path.lowercased())
    }

    /// Writes a `.cmd` script named `name.cmd` into a fresh temporary
    /// directory and returns the directory, so tests can resolve commands
    /// that are not on the test process's `PATH` — covering the `PATHEXT`
    /// name lookup that finds `npx.cmd` for the name `npx`.
    private func makeShimDirectory(named name: String, body: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("calgary-runner-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let shim = directory.appendingPathComponent(name).appendingPathExtension("cmd")
        try "\(body)\r\n".write(to: shim, atomically: true, encoding: .utf8)
        return directory
    }
}
#endif
