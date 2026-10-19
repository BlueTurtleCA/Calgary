import Foundation
import Testing
@testable import Calgary

/// Tests for the real `ProcessCommandRunner`.
///
/// These run small, side-effect-free system commands (`echo`, `sh`, `pwd`)
/// so the production path — PATH resolution, output capture, working
/// directory — is covered without touching the project's files.
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
}
