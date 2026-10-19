import Calgary
import Foundation

/// A virtual root directory for in-memory file systems.
let virtualRoot = URL(fileURLWithPath: "/site")

/// Writes `contents` to `path` (relative to `root`), creating any missing
/// parent directories.
func writeFile(_ contents: String, at path: String, relativeTo root: URL, in fileSystem: any FileSystem) throws {
    let url = root.appendingPathComponent(path)
    try fileSystem.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileSystem.write(Data(contents.utf8), to: url)
}

/// Returns the contents of the file at `path` (relative to `root`), or `nil`
/// if the file does not exist.
func readFile(at path: String, relativeTo root: URL, in fileSystem: any FileSystem) throws -> String? {
    let url = root.appendingPathComponent(path)
    guard fileSystem.fileExists(atPath: url.path) else {
        return nil
    }
    return String(data: try fileSystem.read(contentsOf: url), encoding: .utf8)
}

/// Creates a `CommandResult` from string output.
func commandResult(exitCode: Int32 = 0, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(
        exitCode: exitCode,
        standardOutput: Data(stdout.utf8),
        standardError: Data(stderr.utf8)
    )
}
