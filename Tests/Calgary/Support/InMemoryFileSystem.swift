//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// InMemoryFileSystem.swift
//

import Calgary
import Foundation

/// An in-memory `FileSystem` for tests.
///
/// Files and directories live in dictionaries keyed by normalized absolute
/// path, so builds can run without touching the disk. The semantics mirror
/// `FileManager` for the operations Calgary uses:
///
/// - `write(_:to:)` fails if the parent directory does not exist.
/// - `copyItem(at:to:)` fails if the source is missing or the destination
///   already exists.
/// - `removeItem(at:)` removes directories recursively.
/// - `contentsOfDirectory(at:)` returns the directory's direct children,
///   including hidden files.
final class InMemoryFileSystem: @unchecked Sendable, FileSystem {
    /// The contents of every file, keyed by normalized path.
    private var files: [String: Data] = [:]

    /// The paths of every directory.
    private var directories: Set<String> = ["/"]

    /// The recorded modification date of every file, keyed by normalized
    /// path.
    private var modificationDates: [String: Date] = [:]

    init() {}

    /// Records a modification date for a file, so tests can control the date
    /// the sitemap's `<lastmod>` falls back to.
    func setModificationDate(_ date: Date, of url: URL) {
        modificationDates[normalized(url.path)] = date
    }

    // MARK: - FileSystem

    func fileExists(atPath path: String) -> Bool {
        let path = normalized(path)
        return files[path] != nil || directories.contains(path)
    }

    func isDirectory(atPath path: String) -> Bool {
        directories.contains(normalized(path))
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediate: Bool) throws {
        let path = normalized(url.path)
        guard !directories.contains(path) else { return }

        if createIntermediate {
            var current = path
            while !directories.contains(current) {
                if files[current] != nil {
                    throw InMemoryFileSystemError.invalidFileName(current)
                }
                directories.insert(current)
                current = parentPath(of: current)
            }
        } else {
            guard directories.contains(parentPath(of: path)) else {
                throw InMemoryFileSystemError.noSuchFile(path)
            }
            directories.insert(path)
        }
    }

    func removeItem(at url: URL) throws {
        let path = normalized(url.path)
        guard fileExists(atPath: path) else {
            throw InMemoryFileSystemError.noSuchFile(path)
        }

        files[path] = nil
        directories.remove(path)
        modificationDates[path] = nil

        // Remove everything below the path, if it was a directory.
        let prefix = path + "/"
        for key in files.keys where key.hasPrefix(prefix) {
            files[key] = nil
        }
        for key in modificationDates.keys where key.hasPrefix(prefix) {
            modificationDates[key] = nil
        }
        for key in directories where key.hasPrefix(prefix) {
            directories.remove(key)
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let path = normalized(url.path)
        guard directories.contains(path) else {
            if files[path] != nil {
                throw InMemoryFileSystemError.notADirectory(path)
            }
            throw InMemoryFileSystemError.noSuchFile(path)
        }

        var children: Set<String> = []
        for key in files.keys where parentPath(of: key) == path {
            children.insert(key)
        }
        for key in directories where parentPath(of: key) == path {
            children.insert(key)
        }
        return children.map { URL(fileURLWithPath: $0) }
    }

    func copyItem(at source: URL, to destination: URL) throws {
        let sourcePath = normalized(source.path)
        let destinationPath = normalized(destination.path)

        guard fileExists(atPath: sourcePath) else {
            throw InMemoryFileSystemError.noSuchFile(sourcePath)
        }
        guard !fileExists(atPath: destinationPath) else {
            throw InMemoryFileSystemError.fileExists(destinationPath)
        }

        if let contents = files[sourcePath] {
            files[destinationPath] = contents
            modificationDates[destinationPath] = modificationDates[sourcePath]
        } else {
            directories.insert(destinationPath)
            let prefix = sourcePath + "/"
            for (key, contents) in files where key.hasPrefix(prefix) {
                let destinationKey = destinationPath + String(key.dropFirst(prefix.count))
                files[destinationKey] = contents
                modificationDates[destinationKey] = modificationDates[key]
            }
            for key in directories where key.hasPrefix(prefix) {
                directories.insert(destinationPath + String(key.dropFirst(prefix.count)))
            }
        }
    }

    func write(_ data: Data, to url: URL) throws {
        let path = normalized(url.path)
        guard !directories.contains(path) else {
            throw InMemoryFileSystemError.fileExists(path)
        }
        guard directories.contains(parentPath(of: path)) else {
            throw InMemoryFileSystemError.noSuchFile(path)
        }
        files[path] = data
    }

    func read(contentsOf url: URL) throws -> Data {
        let path = normalized(url.path)
        guard let contents = files[path] else {
            if directories.contains(path) {
                throw InMemoryFileSystemError.notADirectory(path)
            }
            throw InMemoryFileSystemError.noSuchFile(path)
        }
        return contents
    }

    func modificationDate(of url: URL) -> Date? {
        modificationDates[normalized(url.path)]
    }

    // MARK: - Path helpers

    /// Collapses `.` and `..` components and duplicate slashes so that
    /// equivalent paths compare equal.
    private func normalized(_ path: String) -> String {
        var components: [String] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(String(component))
            }
        }
        return "/" + components.joined(separator: "/")
    }

    private func parentPath(of path: String) -> String {
        guard let slashIndex = path.lastIndex(of: "/"), slashIndex > path.startIndex else {
            return "/"
        }
        return String(path[..<slashIndex])
    }
}

/// Errors thrown by `InMemoryFileSystem` to mimic `FileManager` failures.
private enum InMemoryFileSystemError: Error, Equatable {
    case noSuchFile(String)
    case fileExists(String)
    case notADirectory(String)
    case invalidFileName(String)
}
