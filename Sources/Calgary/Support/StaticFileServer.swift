//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// StaticFileServer.swift
//

import Foundation
#if canImport(Network)
import Network
#endif

/// A minimal HTTP server that serves static files from a directory.
///
/// The server exists so a built site can be previewed the way it will be
/// served in production, where absolute paths like `/css/site.css` resolve
/// against the site's root rather than the file system's. It listens on a
/// single port, serves files read-only, and handles GET and HEAD requests.
final class StaticFileServer {
    /// The directory served at the site's root.
    private let root: URL

    /// The file system the files are read from.
    private let fileSystem: any FileSystem

    /// The port the server was asked to listen on.
    private let port: UInt16

    /// Whether hot reload is enabled: the `/__events` endpoint is served and
    /// a reload script is injected into HTML pages.
    private let hotReload: Bool

    /// The open event stream connections, so `broadcast(_:)` can reach them.
    let eventStreams = EventStreamConnections()

    #if canImport(Network)
    private var listener: NWListener?
    #endif

    /// The port the server is listening on.
    ///
    /// Valid after `start()` returns. When the server was created with port
    /// `0`, this is the ephemeral port the system assigned.
    private(set) var assignedPort: UInt16 = 0

    init(root: URL, port: UInt16, fileSystem: any FileSystem, hotReload: Bool = false) {
        self.root = root
        self.port = port
        self.fileSystem = fileSystem
        self.hotReload = hotReload
    }

    /// Starts listening for connections.
    ///
    /// - Throws: `BuildError.portInUse` if the port is already taken, or
    ///   `BuildError.serveUnavailable` on platforms without Network.framework.
    func start() throws {
        #if canImport(Network)
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port))
        let queue = DispatchQueue(label: "Calgary.StaticFileServer")

        let root = self.root
        let fileSystem = self.fileSystem
        let eventStreams = self.eventStreams
        let hotReload = self.hotReload
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.handle(
                connection: connection,
                root: root,
                fileSystem: fileSystem,
                eventStreams: eventStreams,
                hotReload: hotReload
            )
        }

        let started = StartState()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                started.signal()
            case .failed(let error):
                started.fail(with: error)
            default:
                break
            }
        }

        listener.start(queue: queue)
        started.wait()
        if let error = started.error {
            if let nwError = error as? NWError, case .posix(let code) = nwError, code == .EADDRINUSE {
                throw BuildError.portInUse(port: Int(port))
            }
            throw error
        }
        self.assignedPort = listener.port?.rawValue ?? port
        self.listener = listener
        #else
        throw BuildError.serveUnavailable
        #endif
    }

    /// Stops listening for connections and closes any open event streams.
    func stop() {
        #if canImport(Network)
        listener?.cancel()
        listener = nil
        eventStreams.cancelAll()
        #endif
    }

    /// Sends an event to every open event stream connection.
    func broadcast(_ event: String) {
        eventStreams.broadcast(event)
    }
}

// MARK: - Request handling

extension StaticFileServer {
    /// Serves a single connection: reads the request headers, then responds.
    private static func handle(
        connection: NWConnection,
        root: URL,
        fileSystem: any FileSystem,
        eventStreams: EventStreamConnections,
        hotReload: Bool
    ) {
        let buffer = RequestBuffer()
        receiveHeaders(from: connection, into: buffer) {
            respond(
                to: connection,
                request: buffer.data,
                root: root,
                fileSystem: fileSystem,
                eventStreams: eventStreams,
                hotReload: hotReload
            )
        }
    }

    /// Reads data until the request headers are complete, the connection
    /// closes, or the request grows unreasonably large.
    private static func receiveHeaders(
        from connection: NWConnection,
        into buffer: RequestBuffer,
        then finish: @escaping @Sendable () -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
            if let data {
                buffer.data.append(data)
            }
            let complete = isComplete
                || error != nil
                || buffer.data.range(of: headerTerminator) != nil
                || buffer.data.count > 16_384
            if complete {
                finish()
            } else {
                receiveHeaders(from: connection, into: buffer, then: finish)
            }
        }
    }

    private static let headerTerminator = Data("\r\n\r\n".utf8)

    /// Parses the request line and serves the requested path.
    private static func respond(
        to connection: NWConnection,
        request: Data,
        root: URL,
        fileSystem: any FileSystem,
        eventStreams: EventStreamConnections,
        hotReload: Bool
    ) {
        let text = String(data: request, encoding: .utf8) ?? ""
        let firstLine = text.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")

        guard parts.count >= 2 else {
            send(
                connection,
                status: 400,
                reason: "Bad Request",
                contentType: "text/plain; charset=utf-8",
                body: Data("Bad request".utf8)
            )
            return
        }

        switch parts[0] {
        case "GET":
            serve(
                path: String(parts[1]),
                head: false,
                to: connection,
                root: root,
                fileSystem: fileSystem,
                eventStreams: eventStreams,
                hotReload: hotReload
            )
        case "HEAD":
            serve(
                path: String(parts[1]),
                head: true,
                to: connection,
                root: root,
                fileSystem: fileSystem,
                eventStreams: eventStreams,
                hotReload: hotReload
            )
        default:
            send(
                connection,
                status: 405,
                reason: "Method Not Allowed",
                contentType: "text/plain; charset=utf-8",
                body: Data("Method not allowed".utf8)
            )
        }
    }

    /// Maps the requested path to a file under `root` and serves it.
    private static func serve(
        path rawPath: String,
        head: Bool,
        to connection: NWConnection,
        root: URL,
        fileSystem: any FileSystem,
        eventStreams: EventStreamConnections,
        hotReload: Bool
    ) {
        // Strip the query string, if any, and percent-decode the path.
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        let decoded = path.removingPercentEncoding ?? path

        // Reject any attempt to reach above the served root.
        if decoded.split(separator: "/").contains("..") {
            sendNotFound(connection, head: head)
            return
        }

        // The event stream endpoint pushes reload notifications to the
        // browser; it is only available when hot reload is enabled.
        if hotReload, !head, decoded == "/__events" {
            sendEventStream(to: connection, streams: eventStreams)
            return
        }

        var url = root
        for component in decoded.split(separator: "/") where component != "." {
            url = url.appendingPathComponent(String(component))
        }

        // A directory request serves its index.html, if it has one.
        if fileSystem.isDirectory(atPath: url.path) {
            url = url.appendingPathComponent("index.html")
        }

        guard fileSystem.fileExists(atPath: url.path) else {
            sendNotFound(connection, head: head)
            return
        }

        do {
            var body = try fileSystem.read(contentsOf: url)
            let type = contentType(for: url.path)
            // With hot reload on, HTML pages carry a small script that
            // listens for reload notifications on the event stream.
            if !head, hotReload, type.hasPrefix("text/html") {
                body = injectReloadScript(into: body)
            }
            send(
                connection,
                status: 200,
                reason: "OK",
                contentType: type,
                body: body,
                head: head
            )
        } catch {
            sendNotFound(connection, head: head)
        }
    }

    /// Sends an HTTP response and closes the connection.
    private static func send(
        _ connection: NWConnection,
        status: Int,
        reason: String,
        contentType: String?,
        body: Data,
        head: Bool = false
    ) {
        var headers = "HTTP/1.1 \(status) \(reason)\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        if let contentType {
            headers += "Content-Type: \(contentType)\r\n"
        }
        headers += "Connection: close\r\n\r\n"

        var response = Data(headers.utf8)
        if !head {
            response.append(body)
        }
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func sendNotFound(_ connection: NWConnection, head: Bool) {
        send(
            connection,
            status: 404,
            reason: "Not Found",
            contentType: "text/html; charset=utf-8",
            body: notFoundPage,
            head: head
        )
    }

    private static let notFoundPage = Data("""
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><title>404 Not Found</title></head>
        <body><h1>404 Not Found</h1></body>
        </html>
        """.utf8)

    // MARK: - Hot reload

    /// The script injected into served HTML pages so the browser knows to
    /// reload when the site is rebuilt.
    private static let reloadScript = "<script>new EventSource(\"/__events\").addEventListener(\"message\", function () { location.reload(); });</script>"

    /// Inserts the reload script into an HTML document, before `</body>`
    /// when it has one and at the end otherwise.
    private static func injectReloadScript(into body: Data) -> Data {
        guard var text = String(data: body, encoding: .utf8) else { return body }
        if let range = text.range(of: "</body>", options: .backwards) {
            text.insert(contentsOf: reloadScript, at: range.lowerBound)
        } else {
            text += reloadScript
        }
        return Data(text.utf8)
    }

    /// Opens a server-sent events stream: the response headers are sent once
    /// and the connection stays open, receiving `broadcast(_:)` events until
    /// the client disconnects.
    private static func sendEventStream(to connection: NWConnection, streams: EventStreamConnections) {
        var headers = "HTTP/1.1 200 OK\r\n"
        headers += "Content-Type: text/event-stream\r\n"
        headers += "Cache-Control: no-cache\r\n"
        headers += "Connection: keep-alive\r\n"
        headers += "\r\n"
        headers += ": connected\n"

        streams.add(connection)
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { _ in })
        listenForDisconnect(on: connection, streams: streams)
    }

    /// Keeps reading from the connection so a client disconnect is noticed
    /// and the connection is released.
    private static func listenForDisconnect(on connection: NWConnection, streams: EventStreamConnections) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, isComplete, error in
            if isComplete || error != nil {
                streams.remove(connection)
                connection.cancel()
            } else {
                listenForDisconnect(on: connection, streams: streams)
            }
        }
    }

    /// The Content-Type for a file, by extension.
    private static func contentType(for path: String) -> String {
        let fileExtension = path.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
        switch fileExtension {
        case "html", "htm":
            return "text/html; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "js", "mjs":
            return "text/javascript; charset=utf-8"
        case "json", "map":
            return "application/json"
        case "xml":
            return "application/xml"
        case "txt", "md":
            return "text/plain; charset=utf-8"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "ico":
            return "image/x-icon"
        case "pdf":
            return "application/pdf"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        case "eot":
            return "application/vnd.ms-fontobject"
        case "mp4":
            return "video/mp4"
        case "webm":
            return "video/webm"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "ogg":
            return "audio/ogg"
        case "wasm":
            return "application/wasm"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - Helpers

/// Accumulates the bytes of an in-flight request.
private final class RequestBuffer: @unchecked Sendable {
    var data = Data()
}

/// The open event stream connections, shared between the connection
/// handlers and `broadcast(_:)`.
final class EventStreamConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    func add(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
    }

    func remove(_ connection: NWConnection) {
        lock.lock()
        connections.removeAll { $0 === connection }
        lock.unlock()
    }

    var all: [NWConnection] {
        lock.lock()
        defer { lock.unlock() }
        return connections
    }

    /// Sends an event to every open connection, dropping any that fail.
    func broadcast(_ event: String) {
        let payload = Data("data: \(event)\n\n".utf8)
        for connection in all {
            connection.send(content: payload, completion: .contentProcessed { error in
                if error != nil {
                    self.remove(connection)
                }
            })
        }
    }

    func cancelAll() {
        lock.lock()
        let connections = self.connections
        self.connections = []
        lock.unlock()
        for connection in connections {
            connection.cancel()
        }
    }
}

/// A one-shot signal that reports when the listener becomes ready or fails.
private final class StartState: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private var failure: Error?

    func signal() {
        semaphore.signal()
    }

    func fail(with error: Error) {
        failure = error
        semaphore.signal()
    }

    func wait() {
        semaphore.wait()
    }

    var error: Error? {
        failure
    }
}

#if canImport(Network)
private extension NWEndpoint.Port {
    /// Creates a port from a raw value.
    ///
    /// Every `UInt16` is a valid port, so the failable initializer this wraps
    /// cannot fail.
    init(rawValue: UInt16) {
        self.init(rawValue: rawValue)!
    }
}
#endif
