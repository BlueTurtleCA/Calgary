import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// A build step that opens a built page in the default browser.
struct OpenSiteStep: BuildStep {
    /// The page to open, relative to the output directory.
    let page: String

    init(page: String = "index.html") {
        self.page = page
    }

    var name: String {
        "Open '\(page)'"
    }

    func run(site: Site) throws {
        let url = site.outputDirectory.appendingPathComponent(page)
        guard site.fileSystem.fileExists(atPath: url.path) else {
            throw BuildError.missingPath(url.path)
        }
        #if canImport(AppKit)
        _ = NSWorkspace.shared.open(url)
        #endif
    }
}
