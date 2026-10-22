import Foundation
import Testing
@testable import Calgary

@Suite("ServeSiteStep")
struct ServeSiteStepTests {
    private func makeSite(fileSystem: InMemoryFileSystem) -> Site {
        Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
    }

    @Test("Throws when the output directory does not exist")
    func throwsWhenOutputIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let site = makeSite(fileSystem: fileSystem)

        #expect(throws: BuildError.missingPath(virtualRoot.appendingPathComponent("build").path)) {
            try ServeSiteStep(port: 8080).run(site: site)
        }
    }

    @Test("Throws when the port is out of range")
    func throwsWhenPortIsOutOfRange() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(at: virtualRoot.appendingPathComponent("build"), withIntermediateDirectories: true)
        let site = makeSite(fileSystem: fileSystem)

        #expect(throws: BuildError.missingConfiguration("port must be between 0 and 65535")) {
            try ServeSiteStep(port: -1).run(site: site)
        }
    }

    @Test("Describes itself with the port it serves on")
    func nameIncludesPort() {
        #expect(ServeSiteStep(port: 8080, hotReload: false).name == "Serve on port 8080")
    }

    @Test("Mentions hot reload in its name when enabled")
    func nameMentionsHotReload() {
        #expect(ServeSiteStep(port: 8080, hotReload: true).name == "Serve on port 8080 with hot reload")
        #expect(ServeSiteStep(port: 8080, hotReload: false).name == "Serve on port 8080")
    }

    @Test("Serving is a terminal step")
    func serveIsTerminal() {
        #expect(ServeSiteStep(port: 8080).isTerminal)
    }
}
