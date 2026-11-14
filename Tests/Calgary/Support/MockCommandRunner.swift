//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// MockCommandRunner.swift
//

import Calgary
import Foundation

/// A `CommandRunner` for tests.
///
/// The handler simulates the command: it receives the invocation and can
/// write files to the in-memory file system to mimic the command's output.
final class MockCommandRunner: @unchecked Sendable, CommandRunner {
    /// A single recorded invocation.
    struct Invocation: Equatable {
        let command: String
        let arguments: [String]
        let workingDirectory: URL
    }

    /// Every invocation, in the order it was made.
    private(set) var invocations: [Invocation] = []

    /// Simulates the command.
    var handler: @Sendable (String, [String], URL) throws -> CommandResult

    init(handler: @escaping @Sendable (String, [String], URL) throws -> CommandResult) {
        self.handler = handler
    }

    func run(command: String, arguments: [String], workingDirectory: URL) throws -> CommandResult {
        invocations.append(Invocation(command: command, arguments: arguments, workingDirectory: workingDirectory))
        return try handler(command, arguments, workingDirectory)
    }
}
