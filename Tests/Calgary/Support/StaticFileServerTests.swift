//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// StaticFileServerTests.swift
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Calgary

@Suite("StaticFileServer")
struct StaticFileServerTests {
    /// A file system holding a small site to serve, plus a secret file
    /// outside the served root.
    private func makeFileSystem() throws -> InMemoryFileSystem {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(at: virtualRoot.appendingPathComponent("build"), withIntermediateDirectories: true)
        try writeFile("<html>home</html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("body {}", at: "build/css/site.css", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html>fr</html>", at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("top secret", at: "secret.txt", relativeTo: virtualRoot, in: fileSystem)
        return fileSystem
    }

    /// Starts a server on an ephemeral port serving the given file system.
    private func startServer(fileSystem: any FileSystem, hotReload: Bool = false) throws -> StaticFileServer {
        let server = StaticFileServer(
            root: virtualRoot.appendingPathComponent("build"),
            port: 0,
            fileSystem: fileSystem,
            hotReload: hotReload
        )
        try server.start()
        return server
    }

    /// Sends a request to the server and returns the status code, headers,
    /// and body.
    private func request(
        _ server: StaticFileServer,
        _ path: String,
        method: String = "GET"
    ) async throws -> (Int, [String: String], Data) {
        guard let url = URL(string: "http://127.0.0.1:\(server.assignedPort)\(path)") else {
            throw TestError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TestError.notAnHTTPResponse
            }
            return (http.statusCode, Self.headers(of: http), data)
        } catch let error as URLError {
            // The NSURLErrorHTTPResponseKey constant was removed from recent
            // SDKs; the userInfo key is still the same string at runtime.
            guard let http = error.userInfo["NSURLErrorHTTPResponseKey"] as? HTTPURLResponse else {
                throw error
            }
            return (http.statusCode, Self.headers(of: http), Data())
        }
    }

    private static func headers(of response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key.lowercased()] = value
            }
        }
        return headers
    }

    private enum TestError: Error {
        case invalidURL
        case notAnHTTPResponse
    }

    @Test("Serves a file with its contents and content type")
    func servesFile() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        let (status, headers, body) = try await request(server, "/css/site.css")
        #expect(status == 200)
        #expect(headers["content-type"] == "text/css; charset=utf-8")
        #expect(String(data: body, encoding: .utf8) == "body {}")
    }

    @Test("Serves the root as the site's index.html")
    func servesRootIndex() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        let (status, _, body) = try await request(server, "/")
        #expect(status == 200)
        #expect(String(data: body, encoding: .utf8) == "<html>home</html>")
    }

    @Test("Serves a directory as its index.html")
    func servesDirectoryIndex() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        let (status, _, body) = try await request(server, "/fr-fr/")
        #expect(status == 200)
        #expect(String(data: body, encoding: .utf8) == "<html>fr</html>")
    }

    @Test("Returns 404 for a missing file")
    func missingFileIsNotFound() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        let (status, _, _) = try await request(server, "/nope.html")
        #expect(status == 404)
    }

    @Test("Rejects path traversal above the served root")
    func rejectsPathTraversal() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        // Percent-encoded so the URL is not normalized before it is sent.
        let (status, _, body) = try await request(server, "/%2e%2e/secret.txt")
        #expect(status == 404)
        #expect(String(data: body, encoding: .utf8) != "top secret")
    }

    @Test("HEAD returns the headers without a body")
    func headRequestOmitsBody() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        let (status, headers, body) = try await request(server, "/css/site.css", method: "HEAD")
        #expect(status == 200)
        #expect(headers["content-length"] == "7")
        #expect(body.isEmpty)
    }

    @Test("Rejects methods other than GET and HEAD")
    func postIsMethodNotAllowed() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        let (status, _, _) = try await request(server, "/", method: "POST")
        #expect(status == 405)
    }

    @Test("Throws when the port is already in use")
    func portInUseThrows() throws {
        let fileSystem = try makeFileSystem()
        let first = try startServer(fileSystem: fileSystem)
        defer { first.stop() }

        let second = StaticFileServer(
            root: virtualRoot.appendingPathComponent("build"),
            port: first.assignedPort,
            fileSystem: fileSystem
        )
        #expect(throws: BuildError.portInUse(port: Int(first.assignedPort))) {
            try second.start()
        }
    }

    @Test("Injects the reload script before </body> when hot reload is on")
    func injectsReloadScriptBeforeBodyClose() async throws {
        let fileSystem = try makeFileSystem()
        try writeFile("<html><body>page</body></html>", at: "build/page.html", relativeTo: virtualRoot, in: fileSystem)
        let server = try startServer(fileSystem: fileSystem, hotReload: true)
        defer { server.stop() }

        let (status, _, body) = try await request(server, "/page.html")
        #expect(status == 200)
        let html = String(data: body, encoding: .utf8) ?? ""
        let script = html.range(of: "EventSource")
        let bodyClose = html.range(of: "</body>")
        #expect(script != nil)
        #expect(bodyClose != nil)
        if let script, let bodyClose {
            #expect(script.lowerBound < bodyClose.lowerBound)
        }
    }

    @Test("Appends the reload script when the page has no </body>")
    func appendsReloadScriptWithoutBodyClose() async throws {
        let server = try startServer(fileSystem: try makeFileSystem(), hotReload: true)
        defer { server.stop() }

        let (status, _, body) = try await request(server, "/")
        #expect(status == 200)
        let html = String(data: body, encoding: .utf8) ?? ""
        #expect(html.hasPrefix("<html>home</html>"))
        #expect(html.contains("EventSource"))
    }

    @Test("Does not inject the reload script when hot reload is off")
    func noInjectionWhenHotReloadIsOff() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        let (status, _, body) = try await request(server, "/")
        #expect(status == 200)
        #expect(String(data: body, encoding: .utf8) == "<html>home</html>")
    }

    @Test("Does not inject the reload script into non-HTML files")
    func noInjectionIntoCSS() async throws {
        let server = try startServer(fileSystem: try makeFileSystem(), hotReload: true)
        defer { server.stop() }

        let (status, _, body) = try await request(server, "/css/site.css")
        #expect(status == 200)
        #expect(String(data: body, encoding: .utf8) == "body {}")
    }

    @Test("Streams broadcast events to /__events when hot reload is on")
    func eventStreamReceivesBroadcasts() async throws {
        let server = try startServer(fileSystem: try makeFileSystem(), hotReload: true)
        defer { server.stop() }

        guard let url = URL(string: "http://127.0.0.1:\(server.assignedPort)/__events") else {
            throw TestError.invalidURL
        }
        let (bytes, response) = try await URLSession.shared.bytes(for: URLRequest(url: url))
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")

        // The stream opens with a comment line, then receives broadcasts.
        let reader = EventLineReader(bytes: bytes)
        #expect(try await reader.nextLine() == ": connected")

        server.broadcast("reload")
        #expect(try await reader.nextLine() == "data: reload")
    }

    @Test("Returns 404 for /__events when hot reload is off")
    func eventStreamUnavailableWhenHotReloadIsOff() async throws {
        let server = try startServer(fileSystem: try makeFileSystem())
        defer { server.stop() }

        let (status, _, _) = try await request(server, "/__events")
        #expect(status == 404)
    }

    @Test("Stopping the server ends open event streams")
    func stopEndsEventStreams() async throws {
        let server = try startServer(fileSystem: try makeFileSystem(), hotReload: true)
        guard let url = URL(string: "http://127.0.0.1:\(server.assignedPort)/__events") else {
            throw TestError.invalidURL
        }
        let (bytes, _) = try await URLSession.shared.bytes(for: URLRequest(url: url))
        let reader = EventLineReader(bytes: bytes)
        #expect(try await reader.nextLine() == ": connected")

        server.stop()
        #expect(try await reader.nextLine() == nil)
    }
}

/// Reads lines from an event stream one at a time.
private final class EventLineReader {
    private var iterator: URLSession.AsyncBytes.AsyncIterator?

    init(bytes: URLSession.AsyncBytes) {
        iterator = bytes.makeAsyncIterator()
    }

    /// Reads the next line (up to the next newline), or nil when the stream
    /// ends.
    func nextLine() async throws -> String? {
        var line = ""
        while true {
            guard let byte = try await iterator?.next() else {
                return line.isEmpty ? nil : line
            }
            if byte == 0x0A {
                return line
            }
            line.unicodeScalars.append(UnicodeScalar(byte))
        }
    }
}
