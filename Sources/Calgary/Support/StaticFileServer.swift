//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// StaticFileServer.swift
//

import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

/// A minimal HTTP server that serves static files from a directory.
///
/// The server exists so a built site can be previewed the way it will be
/// served in production, where absolute paths like `/css/site.css` resolve
/// against the site's root rather than the file system's. It listens on a
/// single port, serves files read-only, and handles GET and HEAD requests.
/// It is built on SwiftNIO so it runs on macOS, Linux, and Windows.
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

    /// The event loop group that drives the server.
    private var group: MultiThreadedEventLoopGroup?

    /// Temporary bug-hunting hook: exposes the group so a hung test can
    /// print its event loop state.
    var eventLoopGroupForTesting: MultiThreadedEventLoopGroup? { self.group }

    /// The channel accepting incoming connections.
    private var serverChannel: Channel?

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
    /// - Throws: `BuildError.portInUse` if the port is already taken.
    func start() throws {
        // A local dev server needs one event loop thread: it is bound to a
        // local port and serves the traffic of a single browser.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let root = self.root
        let fileSystem = self.fileSystem
        let eventStreams = self.eventStreams
        let hotReload = self.hotReload
        do {
            let bootstrap = ServerBootstrap(group: group)
                .childChannelInitializer { channel in
                    // Runs on the child channel's event loop, so the
                    // synchronous pipeline operations are available.
                    let handler = StaticFileHandler(
                        root: root,
                        fileSystem: fileSystem,
                        eventStreams: eventStreams,
                        hotReload: hotReload
                    )
                    do {
                        try channel.pipeline.syncOperations.addHandlers([
                            HTTPResponseEncoder(configuration: .init()),
                            ByteToMessageHandler(HTTPRequestDecoder()),
                        ])
                        try channel.pipeline.syncOperations.addHandler(handler)
                        return channel.eventLoop.makeSucceededVoidFuture()
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
            // Bind to all interfaces, dual-stack when IPv6 is available and
            // IPv4 only otherwise (some environments disable IPv6).
            let channel: Channel
            do {
                channel = try bootstrap.bind(to: SocketAddress(ipAddress: "::", port: Int(port))).wait()
            } catch {
                channel = try bootstrap.bind(to: SocketAddress(ipAddress: "0.0.0.0", port: Int(port))).wait()
            }
            self.group = group
            self.serverChannel = channel
            self.assignedPort = UInt16(truncatingIfNeeded: channel.localAddress?.port ?? Int(port))
        } catch {
            group.shutdownGracefully { _ in }
            throw Self.bindError(error, port: Int(port))
        }
    }

    /// Stops listening for connections and closes any open event streams.
    ///
    /// The event loop group is shut down but not waited on: the shutdown
    /// completion is delivered through libdispatch, and when the process
    /// cannot spawn new threads (for example under heavy concurrent load),
    /// a synchronous wait here would block the caller forever. Everything
    /// this server needs from the shutdown — closing the channels and
    /// ending the event streams — happens on the event loop thread itself,
    /// so the group's remaining bookkeeping can finish in the background
    /// (or simply be abandoned when the process exits).
    func stop() {
        eventStreams.cancelAll()
        if let serverChannel {
            serverChannel.close(mode: .all, promise: nil)
            self.serverChannel = nil
        }
        if let group {
            group.shutdownGracefully { _ in }
            self.group = nil
        }
    }

    /// Sends an event to every open event stream connection.
    func broadcast(_ event: String) {
        eventStreams.broadcast(event)
    }

    /// Maps a bind failure to the build's port error when the port is
    /// already in use, and passes every other error through unchanged.
    private static func bindError(_ error: Error, port: Int) -> Error {
        if let ioError = error as? IOError, ioError.errnoCode == portInUseCode {
            return BuildError.portInUse(port: port)
        }
        return error
    }

    /// The system error code for "address already in use".
    private static let portInUseCode: Int32 = {
        #if os(Windows)
        // The C runtime's EADDRINUSE is the Winsock code WSAEADDRINUSE.
        return 10048
        #else
        return EADDRINUSE
        #endif
    }()
}

// MARK: - Request handling

/// Serves the site's files to a single connection.
///
/// Every request is answered when its head arrives: GET and HEAD are the only
/// methods the server handles, so no request body is ever read.
private final class StaticFileHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    /// The directory served at the site's root.
    private let root: URL

    /// The file system the files are read from.
    private let fileSystem: any FileSystem

    /// The open event stream connections.
    private let eventStreams: EventStreamConnections

    /// Whether hot reload is enabled.
    private let hotReload: Bool

    init(root: URL, fileSystem: any FileSystem, eventStreams: EventStreamConnections, hotReload: Bool) {
        self.root = root
        self.fileSystem = fileSystem
        self.eventStreams = eventStreams
        self.hotReload = hotReload
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .head(let request) = unwrapInboundIn(data) else {
            // A body part for a request whose head was already answered;
            // nothing more to do.
            return
        }
        handle(request: request, context: context)
    }

    /// A disconnected client is removed from the event stream registry; a
    /// write that fails on a dead connection closes the channel the same way.
    func channelInactive(context: ChannelHandlerContext) {
        eventStreams.remove(context.channel)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    /// Parses the request line and serves the requested path.
    private func handle(request: HTTPRequestHead, context: ChannelHandlerContext) {
        guard request.method == .GET || request.method == .HEAD else {
            Self.respond(
                context: context,
                status: .methodNotAllowed,
                contentType: "text/plain; charset=utf-8",
                body: Data("Method not allowed".utf8),
                head: false
            )
            return
        }
        let head = request.method == .HEAD
        let rawPath = request.uri

        // Strip the query string, if any, and percent-decode the path.
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        let decoded = path.removingPercentEncoding ?? path

        // Reject any attempt to reach above the served root.
        if decoded.split(separator: "/").contains("..") {
            sendNotFound(context, head: head)
            return
        }

        // The event stream endpoint pushes reload notifications to the
        // browser; it is only available when hot reload is enabled.
        if hotReload, !head, decoded == "/__events" {
            startEventStream(context: context)
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
            sendNotFound(context, head: head)
            return
        }

        do {
            var body = try fileSystem.read(contentsOf: url)
            let type = Self.contentType(for: url.path)
            // With hot reload on, HTML pages carry a small script that
            // listens for reload notifications on the event stream.
            if !head, hotReload, type.hasPrefix("text/html") {
                body = Self.injectReloadScript(into: body)
            }
            Self.respond(context: context, status: .ok, contentType: type, body: body, head: head)
        } catch {
            sendNotFound(context, head: head)
        }
    }

    /// Sends an HTTP response and closes the connection.
    ///
    /// The response carries `Connection: close`, matching the server's
    /// previous behavior: the writes are flushed in order and the channel
    /// closes behind them.
    private static func respond(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        contentType: String?,
        body: Data,
        head: Bool
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "\(body.count)")
        if let contentType {
            headers.add(name: "Content-Type", value: contentType)
        }
        headers.add(name: "Connection", value: "close")
        let responseHead = HTTPResponseHead(version: .http1_1, status: status, headers: headers)

        context.write(NIOAny(HTTPServerResponsePart.head(responseHead)), promise: nil)
        if !head {
            context.write(NIOAny(HTTPServerResponsePart.body(IOData.byteBuffer(ByteBuffer(bytes: body)))), promise: nil)
        }
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
        context.close(promise: nil)
    }

    private func sendNotFound(_ context: ChannelHandlerContext, head: Bool) {
        Self.respond(
            context: context,
            status: .notFound,
            contentType: "text/html; charset=utf-8",
            body: Self.notFoundPage,
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
    private func startEventStream(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/event-stream")
        headers.add(name: "Cache-Control", value: "no-cache")
        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)

        context.write(NIOAny(HTTPServerResponsePart.head(responseHead)), promise: nil)
        context.writeAndFlush(
            NIOAny(HTTPServerResponsePart.body(IOData.byteBuffer(ByteBuffer(string: ": connected\n")))),
            promise: nil
        )
        eventStreams.add(context.channel)
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

/// The open event stream connections, shared between the connection
/// handlers and `broadcast(_:)`.
final class EventStreamConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [Channel] = []

    func add(_ channel: Channel) {
        lock.lock()
        channels.append(channel)
        lock.unlock()
    }

    /// Removes a connection, called when its channel goes inactive.
    func remove(_ channel: Channel) {
        lock.lock()
        channels.removeAll { $0 === channel }
        lock.unlock()
    }

    var all: [Channel] {
        lock.lock()
        defer { lock.unlock() }
        return channels
    }

    /// Sends an event to every open connection.
    ///
    /// A write to a dead connection fails, which closes the channel and
    /// removes it via the handler's `channelInactive` callback.
    func broadcast(_ event: String) {
        let part = HTTPServerResponsePart.body(
            IOData.byteBuffer(ByteBuffer(string: "data: \(event)\n\n"))
        )
        for channel in all {
            channel.writeAndFlush(part, promise: nil)
        }
    }

    func cancelAll() {
        lock.lock()
        let channels = self.channels
        self.channels = []
        lock.unlock()
        for channel in channels {
            channel.close(mode: .all, promise: nil)
        }
    }
}
