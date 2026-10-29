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

    /// The date the file at `url` was last modified, or `nil` if the file
    /// does not exist.
    func modificationDate(of url: URL) -> Date?
}

extension FileSystem {
    /// Recursively collects the files under `directory`, sorted by path.
    ///
    /// Directories are not included in the result.
    func files(in directory: URL) throws -> [URL] {
        var results: [URL] = []
        func walk(_ current: URL) throws {
            for entry in try contentsOfDirectory(at: current) {
                if isDirectory(atPath: entry.path) {
                    try walk(entry)
                } else {
                    results.append(entry)
                }
            }
        }
        try walk(directory)
        return results.sorted { $0.path < $1.path }
    }

    /// The path of `url` relative to `base`, or the full path of `url` when
    /// it is not below `base`.
    func relativePath(of url: URL, to base: URL) -> String {
        let basePath = base.path
        let path = url.path
        guard path.hasPrefix(basePath) else { return path }
        return String(path.dropFirst(basePath.count + 1))
    }
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

    public func modificationDate(of url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }
}
