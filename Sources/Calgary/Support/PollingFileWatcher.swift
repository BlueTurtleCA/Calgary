//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// PollingFileWatcher.swift
//

import Foundation

/// A watcher that polls the filesystem on a timer, reporting coalesced batches
/// of changed paths.
///
/// Used on platforms without FSEvents (Linux, Windows): the watched
/// directories are walked every `interval`, a snapshot of the files under
/// them (path → modification date and size) is diffed against the previous
/// one, and any new, changed, or deleted file is handed to `onChange`.
/// Changes are accumulated on the watcher's serial queue and delivered at
/// most once per debounce interval, so a burst of changes (for example, a
/// file save) produces a single callback. `onChange` runs on that same
/// queue, so successive calls never overlap.
///
/// Only files are tracked: directories are not reported, an empty directory
/// appearing or disappearing cannot change a build, and deleting a file
/// (or a directory of files) is reported through the files themselves.
///
/// The walk skips the excluded directories entirely, so a site with a large
/// `node_modules` is not rescanned every poll.
final class PollingFileWatcher: @unchecked Sendable {
    /// The directories to watch.
    private let paths: [URL]

    /// The interval between polls.
    private let interval: TimeInterval

    /// The interval between the last change and the delivery of the batch.
    private let debounce: TimeInterval

    /// The directories skipped while walking (for example, the output
    /// directory and `node_modules`).
    private let excludedDirectories: [URL]

    /// Called with the paths that changed since the last call.
    private let onChange: @Sendable (Set<String>) -> Void

    /// The serial queue that walks the tree and runs `onChange`.
    private let queue = DispatchQueue(label: "Calgary.PollingFileWatcher")

    /// The files' state at the last completed poll, keyed by path.
    private var previousSnapshot: [String: (modificationDate: Date, size: Int)]?

    /// Paths changed since the last delivery, awaiting the debounce.
    private var pendingPaths: Set<String> = []

    /// The scheduled delivery of the pending paths, if any.
    private var pendingWork: DispatchWorkItem?

    /// The scheduled next poll, if any.
    private var pollWork: DispatchWorkItem?

    /// Whether the watcher is running. The poll loop consults it so a tick
    /// scheduled just before `stop()` cannot fire afterwards.
    private var running = false

    /// Creates a watcher.
    ///
    /// - Parameters:
    ///   - paths: The directories to watch.
    ///   - debounce: The interval between the last change and the delivery
    ///     of the batch. Defaults to 0.25 seconds.
    ///   - interval: The interval between polls. Defaults to 0.25 seconds.
    ///   - excludeDirectories: The directories skipped while walking.
    ///     Defaults to an empty list.
    ///   - onChange: Called on the watcher's queue with the paths that
    ///     changed since the last call.
    init(
        paths: [URL],
        debounce: TimeInterval = 0.25,
        interval: TimeInterval = 0.25,
        excludeDirectories: [URL] = [],
        onChange: @escaping @Sendable (Set<String>) -> Void
    ) {
        self.paths = paths
        self.debounce = debounce
        self.interval = interval
        self.excludedDirectories = excludeDirectories
        self.onChange = onChange
    }

    /// Starts polling.
    func start() {
        queue.sync {
            guard !running else { return }
            running = true
            previousSnapshot = snapshot()
        }
        schedulePoll()
    }

    /// Stops polling and cancels the scheduled work.
    func stop() {
        queue.sync {
            running = false
            pollWork?.cancel()
            pollWork = nil
            pendingWork?.cancel()
            pendingWork = nil
            pendingPaths = []
            previousSnapshot = nil
        }
    }

    /// Accumulates a batch of changed paths and schedules its delivery.
    ///
    /// Called from the poll loop on the watcher's queue.
    func handle(changedPaths: Set<String>) {
        guard !changedPaths.isEmpty else { return }
        pendingPaths.formUnion(changedPaths)
        scheduleDelivery()
    }

    private func scheduleDelivery() {
        guard pendingWork == nil else { return }
        let work = DispatchWorkItem { [self] in
            pendingWork = nil
            let paths = pendingPaths
            pendingPaths = []
            onChange(paths)
        }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func schedulePoll() {
        let work = DispatchWorkItem { [self] in
            poll()
        }
        pollWork = work
        queue.asyncAfter(deadline: .now() + interval, execute: work)
    }

    /// Walks the watched directories and delivers any changed paths.
    ///
    /// Called on the watcher's serial queue.
    private func poll() {
        pollWork = nil
        guard running else { return }
        guard let previous = previousSnapshot else {
            schedulePoll()
            return
        }
        let current = snapshot()
        let changed = Self.changedPaths(from: previous, to: current)
        previousSnapshot = current
        if !changed.isEmpty {
            handle(changedPaths: changed)
        }
        schedulePoll()
    }

    /// Takes a snapshot of the files under the watched paths.
    private func snapshot() -> [String: (modificationDate: Date, size: Int)] {
        var result: [String: (modificationDate: Date, size: Int)] = [:]
        var visited = Set<String>()
        for path in paths {
            walk(directory: path, into: &result, visited: &visited)
        }
        return result
    }

    /// Recursively collects the files under `directory`, skipping any
    /// excluded directory.
    ///
    /// `visited` tracks the canonical form of each directory seen in this
    /// walk, so a directory reached through two paths (directly and via a
    /// symlink) is walked once, and a symlink loop cannot recurse forever.
    private func walk(directory: URL, into result: inout [String: (modificationDate: Date, size: Int)], visited: inout Set<String>) {
        guard !isExcluded(directory) else { return }
        guard visited.insert(directory.standardizedFileURL.path).inserted else { return }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        // Report paths in the same form as the watched directories — so a
        // caller comparing a reported path against `site.root`'s path
        // always matches.
        for name in names {
            let entry = directory.appendingPathComponent(name)
            guard !isExcluded(entry) else { continue }
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                walk(directory: entry, into: &result, visited: &visited)
            } else {
                let attributes = try? FileManager.default.attributesOfItem(atPath: entry.path)
                result[entry.path] = (
                    modificationDate: (attributes?[.modificationDate] as? Date) ?? .distantPast,
                    size: (attributes?[.size] as? NSNumber)?.intValue ?? 0
                )
            }
        }
    }

    /// Whether `url` is an excluded directory itself or inside one.
    private func isExcluded(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return excludedDirectories.contains { excluded in
            let excludedPath = excluded.standardizedFileURL.path
            return excludedPath == path || path.hasPrefix(excludedPath + "/")
        }
    }

    /// The paths whose state changed between two snapshots, including
    /// deleted files.
    private static func changedPaths(
        from previous: [String: (modificationDate: Date, size: Int)],
        to current: [String: (modificationDate: Date, size: Int)]
    ) -> Set<String> {
        var changed = Set<String>()
        for (path, entry) in current {
            guard let previousEntry = previous[path] else {
                // A new file.
                changed.insert(path)
                continue
            }
            if previousEntry != entry {
                // The file was modified.
                changed.insert(path)
            }
        }
        for path in previous.keys where current[path] == nil {
            // A deleted file.
            changed.insert(path)
        }
        return changed
    }
}
