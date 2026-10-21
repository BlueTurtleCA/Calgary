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
struct ServeSiteStep: BuildStep {
    /// The port to listen on.
    let port: Int

    init(port: Int = 8080) {
        self.port = port
    }

    var name: String {
        "Serve on port \(port)"
    }

    func run(site: Site) throws {
        guard site.fileSystem.fileExists(atPath: site.outputDirectory.path) else {
            throw BuildError.missingPath(site.outputDirectory.path)
        }
        guard let port = UInt16(exactly: self.port) else {
            throw BuildError.missingConfiguration("port must be between 0 and 65535")
        }

        let server = StaticFileServer(root: site.outputDirectory, port: port, fileSystem: site.fileSystem)
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

        // Block until the process is interrupted. The default disposition
        // of SIGINT and SIGTERM terminates the process, which stops the
        // server with it; there is nothing to clean up.
        DispatchSemaphore(value: 0).wait()
    }
}
