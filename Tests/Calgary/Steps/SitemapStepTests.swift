import Foundation
import Testing
@testable import Calgary

@Suite("SitemapStep")
struct SitemapStepTests {
    @Test("Writes a sitemap of every HTML page, sorted by path")
    func writesSitemapOfEveryPage() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/about.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/blog/post.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("not a page", at: "build/notes.txt", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        #expect(
            try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem) == """
            <?xml version="1.0" encoding="UTF-8"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://example.com/about.html</loc></url>
            <url><loc>https://example.com/blog/post.html</loc></url>
            <url><loc>https://example.com/</loc></url>
            </urlset>
            """
        )
    }

    @Test("Lists index.html files as their directory's URL")
    func listsIndexFilesAsDirectoryURLs() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        #expect(
            try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem) == """
            <?xml version="1.0" encoding="UTF-8"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://example.com/fr-fr/</loc></url>
            <url><loc>https://example.com/</loc></url>
            </urlset>
            """
        )
    }

    @Test("Ignores a trailing slash on the base URL")
    func ignoresTrailingSlashOnBaseUrl() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com/").run(site: site)

        #expect(
            try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem) == """
            <?xml version="1.0" encoding="UTF-8"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://example.com/</loc></url>
            </urlset>
            """
        )
    }

    @Test("Escapes XML characters in URLs")
    func escapesXMLCharactersInURLs() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/weird&name.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        let sitemap = try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem)
        #expect(sitemap?.contains("<url><loc>https://example.com/weird&amp;name.html</loc></url>") == true)
    }

    @Test("Warns and writes nothing when the output has no pages")
    func warnsWhenThereAreNoPages() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("not a page", at: "build/notes.txt", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        #expect(try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem) == nil)
        #expect(site.warnings == ["no pages found in the output directory; 'sitemap.xml' was not written"])
    }

    @Test("Throws when the output directory does not exist")
    func throwsWhenOutputDirectoryIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        let expectedError = BuildError.missingPath(site.outputDirectory.path)

        #expect(throws: expectedError) {
            try SitemapStep(baseUrl: "https://example.com").run(site: site)
        }
    }

    @Test("Describes itself with the base URL")
    func nameIncludesBaseUrl() {
        #expect(SitemapStep(baseUrl: "https://example.com").name == "Generate sitemap for 'https://example.com'")
    }
}
