//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// MinifyStepTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("MinifyStep")
struct MinifyStepTests {
    @Test("Minifies HTML and CSS in the output directory")
    func minifiesHTMLAndCSS() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<div>\n  <!-- c -->\n  <p>Hi</p>\n</div>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("body   {   color:   red;   }", at: "build/css/site.css", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("var a = 1; // keep", at: "build/js/app.js", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try MinifyStep().run(site: site)

        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) == "<div><p>Hi</p></div>")
        #expect(try readFile(at: "build/css/site.css", relativeTo: virtualRoot, in: fileSystem) == "body{color:red;}")
        #expect(try readFile(at: "build/js/app.js", relativeTo: virtualRoot, in: fileSystem) == "var a = 1; // keep")
    }

    @Test("Only minifies files matching the glob")
    func onlyMinifiesMatchingFiles() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<div>  Hi  </div>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("body   {   color:   red;   }", at: "build/css/site.css", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try MinifyStep(glob: "**/*.html").run(site: site)

        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) == "<div> Hi </div>")
        #expect(try readFile(at: "build/css/site.css", relativeTo: virtualRoot, in: fileSystem) == "body   {   color:   red;   }")
    }

    @Test("Skips files that are not HTML or CSS with a warning")
    func skipsUnsupportedFilesWithWarning() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("var a = 1;", at: "build/js/app.js", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try MinifyStep(glob: "**/*").run(site: site)

        #expect(try readFile(at: "build/js/app.js", relativeTo: virtualRoot, in: fileSystem) == "var a = 1;")
        #expect(site.warnings == ["skipped 'js/app.js': only .html and .css files are minified"])
    }

    @Test("Skips files that are not valid UTF-8 with a warning")
    func skipsInvalidUTF8WithWarning() throws {
        let fileSystem = InMemoryFileSystem()
        let url = virtualRoot.appendingPathComponent("build/index.html")
        try fileSystem.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileSystem.write(Data([0xFF, 0xFE, 0x00]), to: url)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try MinifyStep().run(site: site)

        #expect(site.warnings == ["skipped 'index.html': not valid UTF-8"])
    }

    @Test("Throws when the output directory does not exist")
    func throwsWhenOutputDirectoryIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        let expectedError = BuildError.missingPath(site.outputDirectory.path)

        #expect(throws: expectedError) {
            try MinifyStep().run(site: site)
        }
    }

    @Test("Minifies rendered pages when added to the pipeline")
    func minifiesRenderedPagesInPipeline() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Hello
            ---

            Hi!
            """,
            at: "content/index.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            <!doctype html>
            <html>
            <!-- dev: check the header -->
            <head><title>{{ title }}</title></head>
            <body>
              {{ content }}
            </body>
            </html>
            """,
            at: "templates/home.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .renderPages()
            .minify()

        try site.build()

        #expect(
            try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
                == "<!doctype html><html><head><title>Hello</title></head><body><p>Hi!</p></body></html>"
        )
    }

    @Test("Describes itself with the glob it minifies")
    func nameIncludesGlob() {
        #expect(MinifyStep().name == "Minify files matching '**/*.{html,css}'")
    }
}
