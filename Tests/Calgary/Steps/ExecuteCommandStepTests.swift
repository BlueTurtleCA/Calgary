//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// ExecuteCommandStepTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("ExecuteCommandStep")
struct ExecuteCommandStepTests {
    private func makeSite(fileSystem: InMemoryFileSystem, runner: MockCommandRunner) -> Site {
        Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem, commandRunner: runner)
    }

    @Test("Runs the command in the site's root with the given arguments")
    func runsCommandInSiteRoot() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { _, _, _ in commandResult() }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        try site.executeCommand("echo", arguments: ["hello"]).build()

        #expect(runner.invocations == [
            .init(command: "echo", arguments: ["hello"], workingDirectory: virtualRoot)
        ])
    }

    @Test("Fails when the declared input does not exist, without running the command")
    func failsWhenInputIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { _, _, _ in commandResult() }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        #expect(throws: BuildError.missingPath(virtualRoot.appendingPathComponent("assets/css/input.css").path)) {
            try site.executeCommand("tailwind", input: "assets/css/input.css").build()
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test("Runs the command when the declared input exists")
    func runsWhenInputExists() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("input", at: "assets/css/input.css", relativeTo: virtualRoot, in: fileSystem)
        let runner = MockCommandRunner { _, _, _ in commandResult() }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        try site.executeCommand("tailwind", input: "assets/css/input.css").build()

        #expect(runner.invocations.count == 1)
    }

    @Test("Fails when the command exits with a non-zero status, including its error output")
    func failsWhenCommandExitsNonZero() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { _, _, _ in
            commandResult(exitCode: 2, stderr: "could not parse input.css")
        }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        #expect(throws: BuildError.commandFailed(
            command: "tailwind",
            exitCode: 2,
            output: "could not parse input.css"
        )) {
            try site.executeCommand("tailwind").build()
        }
    }

    @Test("Falls back to the command's stdout when it fails without stderr")
    func fallsBackToStdoutOnFailure() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { _, _, _ in
            commandResult(exitCode: 1, stdout: "something went wrong")
        }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        #expect(throws: BuildError.commandFailed(
            command: "tailwind",
            exitCode: 1,
            output: "something went wrong"
        )) {
            try site.executeCommand("tailwind").build()
        }
    }

    @Test("Fails when the declared output is missing after the command runs")
    func failsWhenOutputIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { _, _, _ in commandResult() }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        #expect(throws: BuildError.missingPath(virtualRoot.appendingPathComponent("build/css/site.css").path)) {
            try site.executeCommand("tailwind", output: "build/css/site.css").build()
        }
    }

    @Test("Succeeds when the command produces the declared output")
    func succeedsWhenOutputIsProduced() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { _, _, workingDirectory in
            // Simulate the command creating its output directory and file.
            let outputURL = workingDirectory.appendingPathComponent("build/css/site.css")
            try fileSystem.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileSystem.write(Data("body { margin: 0; }".utf8), to: outputURL)
            return commandResult()
        }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        try site.executeCommand("tailwind", output: "build/css/site.css").build()

        #expect(try readFile(at: "build/css/site.css", relativeTo: virtualRoot, in: fileSystem) == "body { margin: 0; }")
    }

    @Test("Fails when the declared output is a directory")
    func failsWhenOutputIsADirectory() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { _, _, workingDirectory in
            // Simulate the command creating a directory where the file should be.
            // (Anything under the output directory is cleaned before steps run,
            // so the directory must appear while the command runs.)
            try fileSystem.createDirectory(
                at: workingDirectory.appendingPathComponent("build/css/site.css"),
                withIntermediateDirectories: true
            )
            return commandResult()
        }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        #expect(throws: BuildError.unexpectedPathType(
            path: virtualRoot.appendingPathComponent("build/css/site.css").path,
            expected: "file"
        )) {
            try site.executeCommand("tailwind", output: "build/css/site.css").build()
        }
    }

    @Test("Rethrows BuildErrors from the command runner")
    func rethrowsRunnerBuildErrors() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { command, _, _ in
            throw BuildError.commandNotFound(command: command)
        }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        #expect(throws: BuildError.commandNotFound(command: "tailwind")) {
            try site.executeCommand("tailwind").build()
        }
    }

    @Test("Describes itself with the resolved command line")
    func nameIncludesCommandLine() {
        let step = ExecuteCommandStep(
            fallback: CommandInvocation("npx", arguments: ["tailwindcss", "-i", "input.css"]),
            platform: .macOS
        )

        #expect(step.name == "Run 'npx tailwindcss -i input.css'")
    }

    @Test("Selects the platform override when one is declared")
    func selectsPlatformOverride() {
        let fallback = CommandInvocation("npx", arguments: ["build"])
        let windows = CommandInvocation("npx.cmd", arguments: ["build"])

        let onWindows = ExecuteCommandStep(fallback: fallback, windows: windows, platform: .windows)
        #expect(onWindows.invocation == windows)

        let onMacOS = ExecuteCommandStep(fallback: fallback, windows: windows, platform: .macOS)
        #expect(onMacOS.invocation == fallback)

        let onLinux = ExecuteCommandStep(fallback: fallback, windows: windows, platform: .linux)
        #expect(onLinux.invocation == fallback)
    }

    @Test("Selects the fallback on every platform when no overrides are declared")
    func selectsFallbackWithoutOverrides() {
        let fallback = CommandInvocation("npx", arguments: ["build"])

        for platform in Platform.allCases {
            let step = ExecuteCommandStep(fallback: fallback, platform: platform)
            #expect(step.invocation == fallback)
        }
    }

    @Test("Runs the fallback invocation when the platform has no override")
    func runsFallbackInvocation() throws {
        let fileSystem = InMemoryFileSystem()
        let runner = MockCommandRunner { _, _, _ in commandResult() }
        let site = makeSite(fileSystem: fileSystem, runner: runner)

        try site.executeCommand(CommandInvocation("npx", arguments: ["build"])).build()

        #expect(runner.invocations == [
            .init(command: "npx", arguments: ["build"], workingDirectory: virtualRoot)
        ])
    }
}
