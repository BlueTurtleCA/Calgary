//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// ServerShutdownHammerTests.swift
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Calgary

/// The server is only ever touched from one test task at a time; the
/// conformance silences the compiler for the task-group closure.
extension StaticFileServer: @unchecked Sendable {}

/// A small thread-safe boolean flag for the hammer test.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// A small thread-safe bag of result strings for the hammer test.
final class LockedResults: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func record(_ item: String) {
        lock.lock()
        defer { lock.unlock() }
        self.items.append(item)
    }

    func all() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return self.items
    }
}

/// Repeatedly starts and stops real servers to shake out a hang in the
/// event loop group shutdown.
@Suite
struct ServerShutdownHammerTests {
    /// A file system holding one file to serve.
    private func makeFileSystem() throws -> InMemoryFileSystem {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(at: virtualRoot.appendingPathComponent("build"), withIntermediateDirectories: true)
        try writeFile("<html>page</html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        return fileSystem
    }

    private static let dumpLock = NSLock()

    /// Appends a diagnostic dump to a file so it survives a frozen stdout.
    private static func appendDump(_ text: String) {
        dumpLock.lock()
        defer { dumpLock.unlock() }
        let path = "/tmp/calgary-hang-diag.txt"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8) ?? Data())
        } else {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Reads one line of raw bytes from an event stream.
    private static func readOneLine(_ bytes: URLSession.AsyncBytes) async throws -> String? {
        var iterator = bytes.makeAsyncIterator()
        var line = ""
        while true {
            guard let byte = try await iterator.next() else {
                return line.isEmpty ? nil : line
            }
            if byte == 0x0A {
                return line
            }
            line.unicodeScalars.append(UnicodeScalar(byte))
        }
    }

    /// Starts a server, optionally opening an event stream that stays open
    /// while the server stops (as the hot reload tests do), and stops it.
    private static func oneRound(
        fileSystem: any FileSystem,
        openEventStream: Bool,
        results: LockedResults
    ) async {
        var stream: URLSession.AsyncBytes?
        do {
            let newServer = StaticFileServer(
                root: virtualRoot.appendingPathComponent("build"),
                port: 0,
                fileSystem: fileSystem,
                hotReload: openEventStream
            )
            try newServer.start()
            let port = newServer.assignedPort

            let url = URL(string: "http://127.0.0.1:\(port)/index.html")!
            let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                results.record("request failed")
                return
            }

            if openEventStream {
                let streamURL = URL(string: "http://127.0.0.1:\(port)/__events")!
                let (bytes, streamResponse) = try await URLSession.shared.bytes(for: URLRequest(url: streamURL))
                guard (streamResponse as? HTTPURLResponse)?.statusCode == 200 else {
                    results.record("stream request failed")
                    return
                }
                stream = bytes
                _ = try await readOneLine(bytes)
            }

            // The stop must return: a hung shutdown is the bug being hunted.
            // Run it on a real thread, with a watchdog on another real
            // thread (the cooperative pool may itself be starved when the
            // hang happens, so neither stop nor the dump may rely on it).
            let stopDone = LockedFlag()
            DispatchQueue.global().async {
                newServer.stop()
                stopDone.set(true)
            }
            let group = newServer.eventLoopGroupForTesting
            DispatchQueue.global().async {
                Thread.sleep(forTimeInterval: 10)
                guard !stopDone.get() else { return }
                var dump = "HAMMER STOP HUNG port=\(port) stream=\(openEventStream)\n"
                if let group {
                    var iterator = group.makeIterator()
                    while let loop = iterator.next() {
                        // debugDescription shows the external lifecycle
                        // state (.open / .closing / .closed) and the
                        // selector's registrations.
                        dump += "  loop: \(String(reflecting: loop))\n"
                    }
                }
                dump += "  open streams: \(newServer.eventStreams.all.count)\n"
                Self.appendDump(dump)
            }
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline && !stopDone.get() {
                try? await Task.sleep(for: .milliseconds(200))
            }
            if stopDone.get() {
                results.record("ok")
            } else {
                results.record("stop hung")
            }
        } catch {
            results.record("error: \(error)")
        }
        // Dropping the stream releases the client side of the connection.
        stream = nil
    }

    @Test("Starts many servers, some with open event streams, and stops them all at once")
    func concurrentStartStopWithStreams() async throws {
        let fileSystem = try makeFileSystem()
        let results = LockedResults()

        // Burn CPU like the rest of the test suite does while the servers
        // start and stop.
        let loader = Task.detached {
            var sink: UInt64 = 0
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline && !Task.isCancelled {
                for i in 0..<200_000 {
                    sink &+= UInt64(i)
                }
            }
            _ = sink
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    await Self.oneRound(
                        fileSystem: fileSystem,
                        openEventStream: index % 2 == 0,
                        results: results
                    )
                }
            }
        }
        loader.cancel()

        let out = results.all()
        #expect(out.filter { $0 == "ok" }.count == 16, "results: \(out)")
    }
}
