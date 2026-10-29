import Foundation
import Testing
@testable import Calgary

@Suite("CheckLinksStep")
struct CheckLinksStepTests {
    @Test("Resolves absolute and relative links to built pages")
    func resolvesLinksToBuiltPages() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<a href=\"/about.html\"></a>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<a href=\"../about.html\"></a>", at: "build/blog/post.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/about.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings.isEmpty)
    }

    @Test("Resolves links to built assets, not just pages")
    func resolvesLinksToAssets() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<link rel=\"stylesheet\" href=\"/css/site.css\">", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("body {}", at: "build/css/site.css", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings.isEmpty)
    }

    @Test("Warns on internal links that do not resolve")
    func warnsOnBrokenLinks() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<a href=\"/missing.html\"></a>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<a href=\"../missing.html\"></a>", at: "build/blog/post.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/about.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings == [
            "'../missing.html' in 'blog/post.html' does not resolve to a built page",
            "'/missing.html' in 'index.html' does not resolve to a built page",
        ])
    }

    @Test("Skips links with a scheme and fragment-only links")
    func skipsExternalAndFragmentLinks() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            """
            <a href="https://example.com"></a>
            <a href="mailto:hi@example.com"></a>
            <a href="tel:+15550100"></a>
            <a href="#section"></a>
            <a href="?query"></a>
            """,
            at: "build/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings.isEmpty)
    }

    @Test("Ignores fragments and query strings on links to built pages")
    func ignoresFragmentsAndQueryStrings() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            """
            <a href="/about.html#contact"></a>
            <a href="about.html?ref=nav"></a>
            """,
            at: "build/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile("<html></html>", at: "build/about.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings.isEmpty)
    }

    @Test("Resolves a link to a directory to its index.html")
    func resolvesDirectoryLinksToIndex() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            "<a href=\"/blog/\"></a><a href=\"blog/index.html\"></a>",
            at: "build/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile("<html></html>", at: "build/blog/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings.isEmpty)
    }

    @Test("Warns when a linked directory has no index.html")
    func warnsOnDirectoryWithoutIndex() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<a href=\"/blog/\"></a>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/blog/page.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings == ["'/blog/' in 'index.html' does not resolve to a built page"])
    }

    @Test("Decodes percent-encoded characters in links")
    func decodesPercentEncodedLinks() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<a href=\"/my%20page.html\"></a>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/my page.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings.isEmpty)
    }

    @Test("Warns when a link escapes the output directory")
    func warnsWhenALinkEscapesTheOutputDirectory() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<a href=\"../../outside.html\"></a>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings == ["'../../outside.html' in 'index.html' does not resolve to a built page"])
    }

    @Test("Warns once per page for a repeated broken link")
    func warnsOncePerRepeatedLink() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            """
            <a href="/missing.html"></a>
            <a href="/missing.html"></a>
            """,
            at: "build/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings == ["'/missing.html' in 'index.html' does not resolve to a built page"])
    }

    @Test("Reads single-quoted and unquoted hrefs")
    func readsSingleQuotedAndUnquotedHrefs() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            "<a href='/missing.html'></a><a href=missing2.html></a>",
            at: "build/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings == [
            "'/missing.html' in 'index.html' does not resolve to a built page",
            "'missing2.html' in 'index.html' does not resolve to a built page",
        ])
    }

    @Test("Skips files that do not match the glob")
    func skipsFilesOutsideTheGlob() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<a href=\"/missing.html\"></a>", at: "build/notes.txt", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings.isEmpty)
    }

    @Test("Skips a file that is not valid UTF-8 with a warning")
    func skipsNonUTF8Files() throws {
        let fileSystem = InMemoryFileSystem()
        let url = virtualRoot.appendingPathComponent("build/binary.html")
        try fileSystem.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileSystem.write(Data([0xFF, 0xFE, 0x00, 0x01]), to: url)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CheckLinksStep().run(site: site)

        #expect(site.warnings == ["skipped 'binary.html': not valid UTF-8"])
    }

    @Test("Throws when the output directory does not exist")
    func throwsWhenOutputDirectoryIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        let expectedError = BuildError.missingPath(site.outputDirectory.path)

        #expect(throws: expectedError) {
            try CheckLinksStep().run(site: site)
        }
    }

    @Test("Describes itself with the glob")
    func nameIncludesGlob() {
        #expect(CheckLinksStep().name == "Check links in '**/*.html'")
    }
}
