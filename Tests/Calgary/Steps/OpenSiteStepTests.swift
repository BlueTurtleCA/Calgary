import Foundation
import Testing
@testable import Calgary

@Suite("OpenSiteStep")
struct OpenSiteStepTests {
    private func makeSite(fileSystem: InMemoryFileSystem) -> Site {
        Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
    }

    @Test("Throws when the page does not exist in the output directory")
    func throwsWhenPageIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let site = makeSite(fileSystem: fileSystem)

        #expect(throws: BuildError.missingPath(virtualRoot.appendingPathComponent("build/index.html").path)) {
            try OpenSiteStep(page: "index.html").run(site: site)
        }
    }

    @Test("Succeeds when the page exists")
    func succeedsWhenPageExists() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        let site = makeSite(fileSystem: fileSystem)

        try OpenSiteStep(page: "index.html").run(site: site)
    }

    @Test("Describes itself with the page it opens")
    func nameIncludesPage() {
        #expect(OpenSiteStep(page: "index.html").name == "Open 'index.html'")
    }
}
