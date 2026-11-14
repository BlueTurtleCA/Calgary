//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// SitemapStepTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("SitemapStep")
struct SitemapStepTests {
    @Test("Writes a sitemap of every HTML page, sorted by path")
    func writesSitemapOfEveryPage() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/about/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/blog/post/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("not a page", at: "build/notes.txt", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        #expect(
            try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem) == """
            <?xml version="1.0" encoding="UTF-8"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://example.com/about</loc></url>
            <url><loc>https://example.com/blog/post</loc></url>
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
            <url><loc>https://example.com/fr-fr</loc></url>
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
        try writeFile("<html></html>", at: "build/weird&name/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        let sitemap = try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem)
        #expect(sitemap?.contains("<url><loc>https://example.com/weird&amp;name</loc></url>") == true)
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

    @Test("Describes itself without a base URL when the site provides one")
    func nameWithoutBaseUrl() {
        #expect(SitemapStep().name == "Generate sitemap")
    }

    // MARK: Lastmod

    @Test("Writes lastmod from the page's frontmatter date")
    func writesLastmodFromFrontmatterDate() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            """
            ---
            template: home
            date: 2026-01-15
            ---

            Body.
            """,
            at: "content/post.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile("<html></html>", at: "build/post/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        #expect(
            try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem) == """
            <?xml version="1.0" encoding="UTF-8"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://example.com/post</loc><lastmod>2026-01-15T00:00:00Z</lastmod></url>
            </urlset>
            """
        )
    }

    @Test("Falls back to the source file's modification time for lastmod")
    func fallsBackToSourceFileModificationTime() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("---\ntemplate: home\n---\n\nBody.", at: "content/post.md", relativeTo: virtualRoot, in: fileSystem)
        // 2026-01-15T12:30:00Z
        fileSystem.setModificationDate(
            Date(timeIntervalSince1970: 1_768_480_200),
            of: virtualRoot.appendingPathComponent("content/post.md")
        )
        try writeFile("<html></html>", at: "build/post/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        let sitemap = try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem)
        #expect(sitemap?.contains("<lastmod>2026-01-15T12:30:00Z</lastmod>") == true)
    }

    @Test("Falls back to the built file's modification time when there is no source")
    func fallsBackToBuiltFileModificationTime() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/post/index.html", relativeTo: virtualRoot, in: fileSystem)
        // 2026-01-15T12:30:00Z
        fileSystem.setModificationDate(
            Date(timeIntervalSince1970: 1_768_480_200),
            of: virtualRoot.appendingPathComponent("build/post/index.html")
        )

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        let sitemap = try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem)
        #expect(sitemap?.contains("<lastmod>2026-01-15T12:30:00Z</lastmod>") == true)
    }

    @Test("Uses each translation's own frontmatter date for lastmod")
    func usesEachTranslationsFrontmatterDate() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            "---\ntemplate: home\ndate: 2026-01-01\n---\n\nEN.",
            at: "content/index.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "---\ntemplate: home\ndate: 2026-02-01\n---\n\nFR.",
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        let sitemap = try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem)
        #expect(sitemap?.contains("<loc>https://example.com/fr-fr</loc><lastmod>2026-02-01T00:00:00Z</lastmod>") == true)
        #expect(sitemap?.contains("<loc>https://example.com/</loc><lastmod>2026-01-01T00:00:00Z</lastmod>") == true)
    }

    // MARK: Alternates

    @Test("Writes hreflang alternates for localized sites")
    func writesHreflangAlternatesForLocalizedSites() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/blog/post/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        #expect(
            try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem) == """
            <?xml version="1.0" encoding="UTF-8"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
            <url><loc>https://example.com/blog/post</loc><xhtml:link rel="alternate" hreflang="en" href="https://example.com/blog/post"/><xhtml:link rel="alternate" hreflang="x-default" href="https://example.com/blog/post"/></url>
            <url><loc>https://example.com/fr-fr</loc><xhtml:link rel="alternate" hreflang="en" href="https://example.com/"/><xhtml:link rel="alternate" hreflang="fr-fr" href="https://example.com/fr-fr"/><xhtml:link rel="alternate" hreflang="x-default" href="https://example.com/"/></url>
            <url><loc>https://example.com/</loc><xhtml:link rel="alternate" hreflang="en" href="https://example.com/"/><xhtml:link rel="alternate" hreflang="fr-fr" href="https://example.com/fr-fr"/><xhtml:link rel="alternate" hreflang="x-default" href="https://example.com/"/></url>
            </urlset>
            """
        )
    }

    @Test("Writes no alternates when the site is not localized")
    func writesNoAlternatesWithoutLocalization() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("<html></html>", at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        let sitemap = try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem)
        #expect(sitemap?.contains("xhtml") == false)
    }

    // MARK: Base URL

    @Test("Uses the site's base URL when the step has none")
    func usesSiteBaseUrlWhenStepHasNone() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem, baseUrl: "https://example.com")
        try SitemapStep().run(site: site)

        let sitemap = try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem)
        #expect(sitemap?.contains("<loc>https://example.com/</loc>") == true)
    }

    @Test("An explicit base URL overrides the site's")
    func explicitBaseUrlOverridesSiteBaseUrl() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem, baseUrl: "https://site.com")
        try SitemapStep(baseUrl: "https://example.com").run(site: site)

        let sitemap = try readFile(at: "build/sitemap.xml", relativeTo: virtualRoot, in: fileSystem)
        #expect(sitemap?.contains("<loc>https://example.com/</loc>") == true)
    }

    @Test("Throws when no base URL is available")
    func throwsWhenNoBaseUrlIsAvailable() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)

        #expect(throws: BuildError.missingConfiguration(
            "generateSitemap requires a base URL (pass baseUrl: or create the Site with one)"
        )) {
            try SitemapStep().run(site: site)
        }
    }
}
