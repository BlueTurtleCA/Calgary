//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// BuildStep.swift
//

import Foundation

/// A single unit of work in a site build.
///
/// Steps are daisy-chained onto a `Site` and run, in order, when
/// `Site.build()` is called. Each step receives the `Site` it belongs to,
/// which gives it access to the site's resolved paths.
///
/// To add a custom step, conform a type to `BuildStep` and add it to the
/// pipeline with `Site.addStep(_:)`:
///
/// ```swift
/// struct MinifyJavaScriptStep: BuildStep {
///     var name: String { "Minify JavaScript" }
///
///     func run(site: Site) throws {
///         // ...
///     }
/// }
///
/// let site = Site(name: "My Site")
///     .copyAssets(from: "assets")
///     .addStep(MinifyJavaScriptStep())
/// ```
public protocol BuildStep: Sendable {
    /// A short, human-readable description of what this step does.
    ///
    /// Used in build logs and in `BuildError.stepFailed` messages.
    var name: String { get }

    /// Runs the step against the given site.
    ///
    /// - Parameter site: The site being built.
    /// - Throws: A `BuildError` if the step cannot complete.
    func run(site: Site) throws

    /// Whether the step runs once and is skipped when the pipeline is
    /// re-run in place (for example, by the serve step's hot reload).
    ///
    /// Steps that produce output (copying assets, rendering pages) are not
    /// terminal and are re-run; steps that only observe the result (serving,
    /// opening a browser) are terminal and run once.
    var isTerminal: Bool { get }
}

extension BuildStep {
    /// The default for `isTerminal`: steps are re-run when the pipeline is
    /// re-run in place.
    var isTerminal: Bool { false }
}

/// An error that occurs while building a site.
public enum BuildError: Error, Equatable, CustomStringConvertible, Sendable {
    /// A build step threw an error that was not already a `BuildError`.
    case stepFailed(step: String, underlying: Error)

    /// A required path does not exist.
    case missingPath(String)

    /// A build step is missing required configuration.
    case missingConfiguration(String)

    /// A path exists but is not the expected kind of file-system item.
    case unexpectedPathType(path: String, expected: String)

    /// A command's executable could not be found.
    case commandNotFound(command: String)

    /// A command exited with a non-zero status.
    case commandFailed(command: String, exitCode: Int32, output: String)

    /// The port the site server wanted to listen on is already in use.
    case portInUse(port: Int)

    public var description: String {
        switch self {
        case .stepFailed(let step, let underlying):
            return "Build step '\(step)' failed: \(underlying)"
        case .missingPath(let path):
            return "Required path not found: \(path)"
        case .missingConfiguration(let detail):
            return "Missing configuration: \(detail)"
        case .unexpectedPathType(let path, let expected):
            return "Path is not a \(expected): \(path)"
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        case .commandFailed(let command, let exitCode, let output):
            return "Command failed with exit code \(exitCode): \(command)\n\(output)"
        case .portInUse(let port):
            return "Port \(port) is already in use"
        }
    }

    public static func == (lhs: BuildError, rhs: BuildError) -> Bool {
        switch (lhs, rhs) {
        case (.stepFailed(let lhsStep, let lhsError), .stepFailed(let rhsStep, let rhsError)):
            return lhsStep == rhsStep && String(describing: lhsError) == String(describing: rhsError)
        case (.missingPath(let lhsPath), .missingPath(let rhsPath)):
            return lhsPath == rhsPath
        case (.missingConfiguration(let lhsDetail), .missingConfiguration(let rhsDetail)):
            return lhsDetail == rhsDetail
        case (.unexpectedPathType(let lhsPath, let lhsExpected), .unexpectedPathType(let rhsPath, let rhsExpected)):
            return lhsPath == rhsPath && lhsExpected == rhsExpected
        case (.commandNotFound(let lhsCommand), .commandNotFound(let rhsCommand)):
            return lhsCommand == rhsCommand
        case (.commandFailed(let lhsCommand, let lhsExitCode, let lhsOutput),
              .commandFailed(let rhsCommand, let rhsExitCode, let rhsOutput)):
            return lhsCommand == rhsCommand
                && lhsExitCode == rhsExitCode
                && lhsOutput == rhsOutput
        case (.portInUse(let lhsPort), .portInUse(let rhsPort)):
            return lhsPort == rhsPort
        default:
            return false
        }
    }
}
