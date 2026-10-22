import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// A build step that serves the built site over HTTP and opens it in the
/// default browser.
///
/// The server listens on `http://localhost:<port>/` and serves the output
/// directory, so absolute paths in the site (for example, `/css/site.css`)
/// resolve the same way they do in production. The step blocks until the
/// process is interrupted (for example, with Ctrl-C), which stops the
/// server and ends the build.
///
/// When hot reload is enabled, the site's root is watched for file changes.
/// A change re-runs the pipeline's non-terminal steps in place and tells
/// every open browser to reload, so edits to pages, templates, components,
/// and assets (including the CSS source) appear without a manual refresh.
struct ServeSiteStep: BuildStep {
    /// The port to listen on.
    let port: Int

    /// Whether file changes trigger a rebuild and a browser reload.
    let hotReload: Bool

    init(port: Int = 8080, hotReload: Bool = true) {
        self.port = port
        self.hotReload = hotReload
    }

    var name: String {
        hotReload ? "Serve on port \(port) with hot reload" : "Serve on port \(port)"
    }

    var isTerminal: Bool { true }

    func run(site: Site) throws {
        guard site.fileSystem.fileExists(atPath: site.outputDirectory.path) else {
            throw BuildError.missingPath(site.outputDirectory.path)
        }
        guard let port = UInt16(exactly: self.port) else {
            throw BuildError.missingConfiguration("port must be between 0 and 65535")
        }

        let server = StaticFileServer(
            root: site.outputDirectory,
            port: port,
            fileSystem: site.fileSystem,
            hotReload: hotReload
        )
        try server.start()

        // The port is a valid UInt16, so this URL is always valid.
        guard let url = URL(string: "http://localhost:\(server.assignedPort)/") else {
            server.stop()
            throw BuildError.missingConfiguration("invalid port \(port)")
        }
        print("Serving \(site.name) at \(url.absoluteString) (Ctrl-C to stop)")
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif

        #if os(macOS) || os(iOS)
        if hotReload {
            startHotReload(for: site, server: server)
            print("Hot reload on: edit your files and the browser will refresh")
        }
        #else
        if hotReload {
            print("Hot reload is not available on this platform; refresh manually after changes")
        }
        #endif

        // Block until the process is interrupted. The default disposition
        // of SIGINT and SIGTERM terminates the process, which stops the
        // server with it; there is nothing to clean up.
        DispatchSemaphore(value: 0).wait()
    }

    #if os(macOS) || os(iOS)
    /// Starts watching the site's root and, when a watched file changes,
    /// rebuilds the site in place and tells the browsers to reload.
    ///
    /// Changes under the output directory and `node_modules` are ignored:
    /// the first are the rebuild's own writes, the second are the tooling's.
    private func startHotReload(for site: Site, server: StaticFileServer) {
        let outputDirectory = site.outputDirectory.path
        let nodeModules = site.root.appendingPathComponent("node_modules").path
        let streams = server.eventStreams

        let watcher = FileWatcher(paths: [site.root]) { changedPaths in
            let relevant = changedPaths.filter { path in
                !Self.isUnder(path: path, directory: outputDirectory)
                    && !Self.isUnder(path: path, directory: nodeModules)
            }
            guard !relevant.isEmpty else { return }

            print("Change detected; rebuilding")
            do {
                try site.rebuild()
                print("Rebuild complete; reloading")
                streams.broadcast("reload")
            } catch {
                print("Rebuild failed: \(error)")
            }
        }
        watcher.start()
    }
    #endif

    /// Whether `path` is `directory` itself or inside it.
    private static func isUnder(path: String, directory: String) -> Bool {
        path == directory || path.hasPrefix(directory + "/")
    }
}
