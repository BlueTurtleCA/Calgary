import Foundation
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
    private func startServer(fileSystem: any FileSystem) throws -> StaticFileServer {
        let server = StaticFileServer(
            root: virtualRoot.appendingPathComponent("build"),
            port: 0,
            fileSystem: fileSystem
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
}
