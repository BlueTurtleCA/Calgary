import Foundation

/// Abstraction over the file-system operations Calgary's build steps need.
///
/// `Site` performs all of its file I/O through a `FileSystem`, so builds can
/// run against the local disk (the default, `LocalFileSystem`) or against an
/// in-memory stand-in in tests.
public protocol FileSystem: Sendable {
    /// Whether a file or directory exists at `path`.
    func fileExists(atPath path: String) -> Bool

    /// Whether the item at `path` is a directory.
    ///
    /// Returns `false` if the item does not exist.
    func isDirectory(atPath path: String) -> Bool

    /// Creates a directory at `url`.
    ///
    /// - Parameters:
    ///   - url: The directory to create.
    ///   - withIntermediateDirectories: Whether missing parent directories
    ///     should be created as well.
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws

    /// Removes the item (file or directory) at `url`.
    ///
    /// Directories are removed recursively.
    func removeItem(at url: URL) throws

    /// Returns the URLs of the items directly contained in the directory at
    /// `url`, including hidden files.
    func contentsOfDirectory(at url: URL) throws -> [URL]

    /// Copies the item at `source` to `destination`.
    ///
    /// - Parameters:
    ///   - source: The item to copy.
    ///   - destination: The destination. Must not already exist.
    func copyItem(at source: URL, to destination: URL) throws

    /// Writes `data` to the file at `url`, overwriting any existing file.
    ///
    /// The parent directory must already exist.
    func write(_ data: Data, to url: URL) throws

    /// Returns the contents of the file at `url`.
    func read(contentsOf url: URL) throws -> Data
}

/// A `FileSystem` backed by `FileManager`.
public struct LocalFileSystem: FileSystem {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isDirectory(atPath path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: withIntermediateDirectories
        )
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    public func read(contentsOf url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}
