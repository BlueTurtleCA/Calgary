//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// PollingFileWatcherTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("PollingFileWatcher")
struct PollingFileWatcherTests {
    /// How often the watcher polls, and how long the debounce waits.
    private static let interval: TimeInterval = 0.2
    private static let debounce: TimeInterval = 0.1

    /// How long each wait tolerates before failing.
    private static let budget: TimeInterval = 5

    /// A directory the watcher watches, created under the system temp dir.
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("calgary-polling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// An object that collects the batches the watcher delivers.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var _batches: [[String]] = []

        func add(_ paths: Set<String>) {
            lock.lock()
            _batches.append(Array(paths))
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return _batches.count
        }

        func all() -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            return Set(_batches.flatMap { $0 })
        }
    }

    /// A watcher that delivers its batches to `collector`.
    private func makeWatcher(paths: [URL], excludeDirectories: [URL] = [], collector: Collector) -> PollingFileWatcher {
        PollingFileWatcher(
            paths: paths,
            debounce: Self.debounce,
            interval: Self.interval,
            excludeDirectories: excludeDirectories,
            onChange: { paths in collector.add(paths) }
        )
    }

    /// Waits until `condition` is true, or returns false after the budget expires.
    private func waitFor(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(Self.budget)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

    /// Writes `contents` to `url`, creating parent directories as needed.
    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    @Test("Reports a modified file")
    func reportsModifiedFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("index.md")
        try write("one", to: file)

        let collector = Collector()
        let watcher = makeWatcher(paths: [directory], collector: collector)
        watcher.start()
        defer { watcher.stop() }

        try write("one completely different file", to: file)
        #expect(waitFor { collector.all().contains(file.path) })
    }

    @Test("Reports a newly created file")
    func reportsNewFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let collector = Collector()
        let watcher = makeWatcher(paths: [directory], collector: collector)
        watcher.start()
        defer { watcher.stop() }

        let file = directory.appendingPathComponent("blog/post.md")
        try write("hello", to: file)
        #expect(waitFor { collector.all().contains(file.path) })
    }

    @Test("Reports a deleted file")
    func reportsDeletedFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("index.md")
        try write("hello", to: file)

        let collector = Collector()
        let watcher = makeWatcher(paths: [directory], collector: collector)
        watcher.start()
        defer { watcher.stop() }

        try FileManager.default.removeItem(at: file)
        #expect(waitFor { collector.all().contains(file.path) })
    }

    @Test("Ignores the excluded directories")
    func ignoresExcludedDirectories() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let watched = directory.appendingPathComponent("src/index.md")
        let skipped = directory.appendingPathComponent("node_modules/lib.js")
        try write("one", to: watched)
        try write("one", to: skipped)

        let collector = Collector()
        let watcher = makeWatcher(
            paths: [directory],
            excludeDirectories: [directory.appendingPathComponent("node_modules")],
            collector: collector
        )
        watcher.start()
        defer { watcher.stop() }

        try write("a different amount of content", to: watched)
        try write("a different amount of content", to: skipped)
        #expect(waitFor { collector.all().contains(watched.path) })
        #expect(!collector.all().contains(skipped.path))
    }

    @Test("Coalesces a burst of changes into a single batch")
    func coalescesBurstsIntoASingleBatch() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("a.md")
        let second = directory.appendingPathComponent("b.md")

        let collector = Collector()
        let watcher = makeWatcher(paths: [directory], collector: collector)
        watcher.start()
        defer { watcher.stop() }

        try write("first", to: first)
        try write("second", to: second)
        #expect(waitFor { collector.all().contains(first.path) })
        #expect(collector.all().contains(second.path))
        #expect(collector.count == 1)
    }

    @Test("Stops delivering after stop")
    func stopsDeliveringAfterStop() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("index.md")
        try write("one", to: file)

        let collector = Collector()
        let watcher = makeWatcher(paths: [directory], collector: collector)
        watcher.start()
        watcher.stop()

        try write("a different amount of content", to: file)
        // Give any scheduled tick (if it somehow survived stop) a chance to run.
        Thread.sleep(forTimeInterval: 1.0)
        #expect(collector.count == 0)
    }
}
