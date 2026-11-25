//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// RenderPagesStepTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("RenderPagesStep")
struct RenderPagesStepTests {
    private func makeSite(fileSystem: InMemoryFileSystem) -> Site {
        Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
    }

    /// Seeds a file system with a minimal site: one page, one template, one
    /// component.
    private func seedMinimalSite(fileSystem: InMemoryFileSystem) throws {
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Hello
            ---

            Hi, welcome to {{ title }}!
            """,
            at: "content/index.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            <!doctype html>
            <html>
            <head><title>{{ title }}</title></head>
            <body>
            {% include "components/header" %}
            {{ content }}
            </body>
            </html>
            """,
            at: "templates/home.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<header>{{ site.name }}</header>",
            at: "components/header.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
    }

    @Test("Renders a page into its template")
    func rendersPageIntoTemplate() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output != nil)
        #expect(output?.contains("<title>Hello</title>") == true)
        #expect(output?.contains("<header>Test Site</header>") == true)
        #expect(output?.contains("<p>Hi, welcome to Hello!</p>") == true)
    }

    @Test("Renders a page with Windows line endings")
    func rendersPageWithCRLFLineEndings() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        // A page checked out with CRLF endings on Windows.
        try writeFile(
            "---\r\n"
            + "template: home\r\n"
            + "variables:\r\n"
            + "  title: A Post\r\n"
            + "---\r\n"
            + "\r\n"
            + "A post.\r\n",
            at: "content/crlf.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/crlf/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("<title>A Post</title>") == true)
        #expect(output?.contains("<p>A post.</p>") == true)
    }

    @Test("Mirrors the source path in the output")
    func mirrorsSourcePathInOutput() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: A Post
            ---

            A post.
            """,
            at: "content/blog/post.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        #expect(try readFile(at: "build/blog/post/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
    }

    @Test("Publishes a page at its slug")
    func publishesAPageAtItsSlug() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            slug: hello-world
            variables:
              title: A Post
            ---

            {{ page.url }}
            """,
            at: "content/blog/post.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        // The page builds to the slug's path, not the file name's.
        #expect(try readFile(at: "build/blog/hello-world/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/blog/post/index.html", relativeTo: virtualRoot, in: fileSystem) == nil)

        let output = try readFile(at: "build/blog/hello-world/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("/blog/hello-world") == true)
    }

    @Test("A slug may nest the page under a subpath")
    func slugMayNestThePageUnderASubpath() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            slug: 2026-01-05/hello-world
            variables:
              title: A Post
            ---

            {{ page.url }}
            """,
            at: "content/blog/post.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        #expect(try readFile(at: "build/blog/2026-01-05/hello-world/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)

        let output = try readFile(at: "build/blog/2026-01-05/hello-world/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("/blog/2026-01-05/hello-world") == true)
    }

    @Test("Fails when two pages build to the same path")
    func failsWhenTwoPagesBuildToTheSamePath() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            "---\ntemplate: home\nslug: shared\ntitle: One\n---\n\nOne.",
            at: "content/blog/one.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "---\ntemplate: home\nslug: shared\ntitle: Two\n---\n\nTwo.",
            at: "content/blog/two.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        #expect(throws: BuildError.self) {
            try site.build()
        }
    }

    @Test("Fails when a slug contains a parent-directory segment")
    func failsWhenASlugContainsAParentDirectorySegment() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            "---\ntemplate: home\nslug: ../escape\ntitle: Escaping\n---\n\nBody.",
            at: "content/blog/post.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        #expect(throws: BuildError.self) {
            try site.build()
        }
    }

    @Test("Exposes the built-in variables")
    func exposesBuiltInVariables() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            date: 2026-01-01
            variables:
              title: Dated
            ---

            {{ page.url }} / {{ page.date }}
            """,
            at: "content/dated.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/dated/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("/dated / 2026-01-01") == true)
    }

    @Test("Exposes the current year as site.year")
    func exposesCurrentYearAsSiteYear() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Year
            ---

            {{ site.year }}
            """,
            at: "content/year.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let year = Calendar.current.component(.year, from: .now)
        let output = try readFile(at: "build/year/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("<p>\(year)</p>") == true)
    }

    @Test("Exposes page.canonical when the site has a base URL")
    func exposesCanonicalWhenSiteHasBaseUrl() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            <!doctype html>
            <html>
            <head><title>{{ title }}</title><link rel="canonical" href="{{ page.canonical }}"></head>
            <body>{{ content }}</body>
            </html>
            """,
            at: "templates/home.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            ---
            template: home
            variables:
              title: A Post
            ---

            A post.
            """,
            at: "content/blog/post.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = Site(
            name: "Test Site",
            root: virtualRoot,
            fileSystem: fileSystem,
            baseUrl: "https://example.com"
        )
        .registerTemplates(in: "templates")
        .registerComponents(in: "components")
        .renderPages()

        try site.build()

        let index = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(index?.contains("<link rel=\"canonical\" href=\"https://example.com/\">") == true)

        let post = try readFile(at: "build/blog/post/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(post?.contains("<link rel=\"canonical\" href=\"https://example.com/blog/post\">") == true)
    }

    @Test("Does not expose page.canonical when the site has no base URL")
    func noCanonicalWithoutBaseUrl() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            <!doctype html>
            <html>
            <head>{% if page.canonical %}CANONICAL{% endif %}</head>
            <body>{{ content }}</body>
            </html>
            """,
            at: "templates/home.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("CANONICAL") == false)
    }

    @Test("Exposes site template variables under the site namespace")
    func exposesSiteTemplateVariables() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Vars
            ---

            {{ site.year }}
            """,
            at: "content/vars.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = Site(
            name: "Test Site",
            root: virtualRoot,
            fileSystem: fileSystem,
            templateVariables: ["year": .string("2026")]
        )
        .registerTemplates(in: "templates")
        .registerComponents(in: "components")
        .renderPages()

        try site.build()

        let output = try readFile(at: "build/vars/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("<p>2026</p>") == true)
    }

    @Test("Site template variables override built-in site variables")
    func siteTemplateVariablesOverrideBuiltIns() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)

        let site = Site(
            name: "Test Site",
            root: virtualRoot,
            fileSystem: fileSystem,
            templateVariables: ["name": .string("Override")]
        )
        .registerTemplates(in: "templates")
        .registerComponents(in: "components")
        .renderPages()

        try site.build()

        let output = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("<header>Override</header>") == true)
    }

    @Test("Throws when templates are not registered")
    func throwsWhenTemplatesAreNotRegistered() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .renderPages()

        #expect(throws: BuildError.missingConfiguration("renderPages requires registerTemplates(in:)")) {
            try site.build()
        }
    }

    @Test("Throws when the templates directory does not exist")
    func throwsWhenTemplatesDirectoryIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "no-such-directory")
            .renderPages()

        #expect(throws: BuildError.missingPath(virtualRoot.appendingPathComponent("no-such-directory").path)) {
            try site.build()
        }
    }

    @Test("Throws when the page's template does not exist")
    func throwsWhenTemplateIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            """
            ---
            template: missing
            ---
            Body.
            """,
            at: "content/index.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile("<html></html>", at: "templates/home.html", relativeTo: virtualRoot, in: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")

        #expect(throws: TemplateError.templateNotFound("missing")) {
            try RenderPagesStep(glob: "**/*.md").run(site: site)
        }
    }

    @Test("Throws when the source directory does not exist")
    func throwsWhenSourceDirectoryIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "templates/home.html", relativeTo: virtualRoot, in: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .renderPages()

        #expect(throws: BuildError.missingPath(virtualRoot.appendingPathComponent("content").path)) {
            try site.build()
        }
    }

    @Test("Throws when a page has no frontmatter")
    func throwsWhenPageHasNoFrontmatter() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile("Just a body, no frontmatter.", at: "content/index.md", relativeTo: virtualRoot, in: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")

        #expect(throws: FrontmatterError.missingOpeningDelimiter) {
            try RenderPagesStep(glob: "**/*.md").run(site: site)
        }
    }

    @Test("Renders markdown components included by a page")
    func rendersMarkdownComponentsIncludedByPage() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            "## {{ title }}\n\nA calm corner of the web.",
            at: "components/hero.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Hello
            ---

            {% include "components/hero" %}
            """,
            at: "content/hero-page.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/hero-page/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("<h2>Hello</h2>") == true)
        #expect(output?.contains("<p>A calm corner of the web.</p>") == true)
    }

    @Test("Renders only files matching the glob")
    func rendersOnlyFilesMatchingTheGlob() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Nested
            ---

            Nested page.
            """,
            at: "content/nested/page.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/nested/page/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
    }

    @Test("Renders an HTML page standalone, without markdown or a template")
    func rendersHTMLPageStandalone() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            """
            ---
            variables:
              title: Hello
            ---
            <!doctype html>
            <html>
            <head><title>{{ title }}</title></head>
            <body>
            {% include "components/header" %}
            <main>
            **not markdown**
            </main>
            </body>
            </html>
            """,
            at: "content/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<header>{{ site.name }}</header>",
            at: "components/header.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output != nil)
        #expect(output?.contains("<title>Hello</title>") == true)
        #expect(output?.contains("<header>Test Site</header>") == true)
        #expect(output?.contains("**not markdown**") == true)
    }

    @Test("Mirrors the source path for HTML pages")
    func mirrorsSourcePathForHTMLPages() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            "<html><body>Nested</body></html>",
            at: "content/nested/page.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .renderPages()

        try site.build()

        #expect(try readFile(at: "build/nested/page/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/nested/page.html", relativeTo: virtualRoot, in: fileSystem) == nil)
    }

    @Test("Throws when an HTML page declares a template")
    func throwsWhenHTMLPageDeclaresTemplate() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            "---\ntemplate: home\n---\n<html></html>",
            at: "content/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")

        #expect(throws: FrontmatterError.templateNotAllowedInHTMLPage) {
            try RenderPagesStep(glob: "**/*.{md,html}").run(site: site)
        }
    }

    @Test("A glob can restrict which pages render")
    func globRestrictsWhichPagesRender() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            "<html><body>Raw</body></html>",
            at: "content/raw.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages(glob: "**/*.md")

        try site.build()

        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/raw.html", relativeTo: virtualRoot, in: fileSystem) == nil)
    }

    @Test("Writes translations under a locale subfolder")
    func writesTranslationsUnderLocaleSubfolder() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Bonjour
            ---

            Bonjour le monde.
            """,
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/fr-fr/index.fr-fr.html", relativeTo: virtualRoot, in: fileSystem) == nil)
    }

    @Test("Writes HTML translations under a locale subfolder")
    func writesHTMLTranslationsUnderLocaleSubfolder() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            "<html><body>EN</body></html>",
            at: "content/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<html><body>FR</body></html>",
            at: "content/index.fr-fr.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
            .renderPages()

        try site.build()

        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/fr-fr/index.fr-fr.html", relativeTo: virtualRoot, in: fileSystem) == nil)

        // The explicit translation file wins over the default page.
        let french = try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(french?.contains("FR") == true)
        #expect(french?.contains("EN") == false)
        #expect(site.warnings.isEmpty)
    }

    @Test("Renders a default-locale HTML page for every declared locale")
    func rendersHTMLPageForEveryDeclaredLocale() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            """
            {
              "sourceLanguage" : "en",
              "strings" : {
                "greeting" : {
                  "localizations" : {
                    "en" : { "stringUnit" : { "state" : "translated", "value" : "Hello" } },
                    "fr-FR" : { "stringUnit" : { "state" : "translated", "value" : "Bonjour" } }
                  }
                }
              },
              "version" : "1.0"
            }
            """,
            at: "Localizable.xcstrings",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<html><body>{{ strings.greeting }} ({{ page.locale }})</body></html>",
            at: "content/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "Localizable.xcstrings")
            .renderPages()

        try site.build()

        let english = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(english?.contains("Hello (en)") == true)

        let french = try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(french?.contains("Bonjour (fr-fr)") == true)
        #expect(site.warnings.isEmpty)
    }

    @Test("Warns when a markdown page has no translation")
    func warnsWhenMarkdownPageHasNoTranslation() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem) == nil)
        #expect(site.warnings == ["no 'fr-fr' version of 'index.md' found; 'fr-fr/index.html' was not rendered"])
    }

    @Test("Emits hreflang alternates for every locale an HTML page renders for")
    func emitsAlternatesForEveryLocaleAnHTMLPageRendersFor() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            "<html><head>{{ page.alternates }}</head><body>EN</body></html>",
            at: "content/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr", "de"])
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"en\" href=\"/\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"fr-fr\" href=\"/fr-fr\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"de\" href=\"/de\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"x-default\" href=\"/\">") == true)

        #expect(try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/de/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
    }

    @Test("A locale-suffixed file is an ordinary page when the site is not localized")
    func localeSuffixedFileWithoutLocalization() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Weird
            ---

            Body.
            """,
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        #expect(try readFile(at: "build/index.fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem) == nil)
    }

    @Test("Exposes the locale built-in variables")
    func exposesLocaleBuiltInVariables() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Bonjour
            ---

            {{ page.locale }} / {{ site.defaultLocale }} / {{ page.url }}
            """,
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("fr-fr / en / /fr-fr") == true)
    }

    @Test("Emits hreflang alternates only for locales that have the page")
    func emitsHreflangAlternatesOnlyForExistingTranslations() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Bonjour
            ---

            Bonjour.
            """,
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            <!doctype html>
            <html>
            <head>
            <title>{{ title }}</title>
            {{ page.alternates }}
            </head>
            <body>{{ content }}</body>
            </html>
            """,
            at: "templates/home.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr", "de"])
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output != nil)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"en\" href=\"/\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"fr-fr\" href=\"/fr-fr\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"x-default\" href=\"/\">") == true)
        #expect(output?.contains("hreflang=\"de\"") == false)
    }

    @Test("Emits hreflang alternates for HTML pages")
    func emitsHreflangAlternatesForHTMLPages() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile(
            "<html><head>{{ page.alternates }}</head><body>EN</body></html>",
            at: "content/index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<html><body>FR</body></html>",
            at: "content/index.fr-fr.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"en\" href=\"/\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"fr-fr\" href=\"/fr-fr\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"x-default\" href=\"/\">") == true)
    }

    @Test("Resolves localized strings with fallback to the default locale")
    func resolvesLocalizedStringsWithFallback() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            nav:
              home: Home
              about: About
            """,
            at: "strings/en.yaml",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            nav:
              home: Accueil
            """,
            at: "strings/fr-fr.yaml",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<header>{{ strings.nav.home }} / {{ strings.nav.about }}</header>",
            at: "components/header.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Bonjour
            ---

            Bonjour.
            """,
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "strings")
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let french = try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(french?.contains("<header>Accueil / About</header>") == true)

        let english = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(english?.contains("<header>Home / About</header>") == true)
    }

    @Test("Expands placeholders in localized strings")
    func expandsPlaceholdersInLocalizedStrings() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            <!doctype html>
            <html>
            <head><title>{{ title }}</title></head>
            <body>
            {% include "components/header" %}
            {{ content }}
            {% include "components/footer" %}
            </body>
            </html>
            """,
            at: "templates/home.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            footer:
              copyright: Copyright {{ site.year }} Test Site. All rights reserved.
            """,
            at: "strings/en.yaml",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            footer:
              copyright: © {{ site.year }} Test Site. Tous droits réservés.
            """,
            at: "strings/fr-fr.yaml",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<footer>{{ strings.footer.copyright }}</footer>",
            at: "components/footer.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Bonjour
            ---

            Bonjour.
            """,
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "strings")
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let year = Calendar.current.component(.year, from: .now)
        let english = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(english?.contains("<footer>Copyright \(year) Test Site. All rights reserved.</footer>") == true)

        let french = try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(french?.contains("<footer>© \(year) Test Site. Tous droits réservés.</footer>") == true)
    }

    @Test("Throws when the strings directory does not exist")
    func throwsWhenStringsDirectoryIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "no-such-directory")
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        #expect(throws: BuildError.missingPath(virtualRoot.appendingPathComponent("no-such-directory").path)) {
            try site.build()
        }
    }

    @Test("Renders pages with strings from a string catalog")
    func rendersPagesWithStringsFromACatalog() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            {
              "sourceLanguage" : "en",
              "strings" : {
                "nav.home" : {
                  "localizations" : {
                    "en" : { "stringUnit" : { "state" : "translated", "value" : "Home" } },
                    "fr-FR" : { "stringUnit" : { "state" : "translated", "value" : "Accueil" } }
                  }
                }
              },
              "version" : "1.0"
            }
            """,
            at: "Localizable.xcstrings",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<header>{{ strings.nav.home }}</header>",
            at: "components/header.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Bonjour
            ---

            Bonjour.
            """,
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "Localizable.xcstrings")
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let french = try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(french?.contains("<header>Accueil</header>") == true)

        let english = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(english?.contains("<header>Home</header>") == true)
    }

    @Test("Throws when the strings path is a file that is not a catalog")
    func throwsWhenStringsPathIsNotACatalog() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile("nav:\n  home: Home\n", at: "strings.yaml", relativeTo: virtualRoot, in: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "strings.yaml")
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        #expect(throws: BuildError.unexpectedPathType(
            path: virtualRoot.appendingPathComponent("strings.yaml").path,
            expected: "a directory of YAML string files or a .xcstrings catalog"
        )) {
            try site.build()
        }
    }

    // MARK: Page collection

    @Test("Exposes the site's pages as site.pages")
    func exposesSitePages() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: About
            ---

            {% for page in site.pages %}<a href="{{ page.url }}">{{ page.title }}</a>{% endfor %}
            """,
            at: "content/about.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/about/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("<a href=\"/\">Hello</a>") == true)
        #expect(output?.contains("<a href=\"/about\">About</a>") == true)
    }

    @Test("site.pages includes a page's date when declared")
    func sitePagesIncludeDate() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            date: 2026-02-01
            variables:
              title: Dated
            ---

            {% for page in site.pages %}{% if page.date %}{{ page.date }}{% endif %}{% endfor %}
            """,
            at: "content/dated.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/dated/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("2026-02-01") == true)
    }

    @Test("site.pages falls back to the file name when a page has no title")
    func sitePagesFallBackToFileName() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        // An HTML page has no frontmatter, so its site.pages entry falls back
        // to the file name.
        try writeFile(
            "<html><body>untitled page</body></html>",
            at: "content/untitled.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            ---
            template: home
            variables:
              title: List
            ---

            {% for page in site.pages %}{{ page.title }}{% endfor %}
            """,
            at: "content/list.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/list/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("untitled") == true)
    }

    @Test("site.pages exposes each page's locale")
    func sitePagesExposeLocale() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            variables:
              title: Bonjour
            ---

            {% for page in site.pages %}{{ page.locale }}{% endfor %}
            """,
            at: "content/index.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let french = try readFile(at: "build/fr-fr/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(french?.contains("en") == true)
        #expect(french?.contains("fr-fr") == true)
    }

    @Test("site.pages exposes each page's frontmatter variables")
    func sitePagesExposeFrontmatterVariables() throws {
        let fileSystem = InMemoryFileSystem()
        try seedMinimalSite(fileSystem: fileSystem)
        try writeFile(
            """
            ---
            template: home
            title: A Post
            description: A short description.
            ---

            {% for page in site.pages where url == "/post" %}{{ page.description }}{% endfor %}
            """,
            at: "content/post.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/post/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("A short description.") == true)
    }

    // MARK: Collections

    /// Seeds a file system with a collection: a post template, an index
    /// template, and two posts in content/blog.
    private func seedCollectionSite(fileSystem: InMemoryFileSystem) throws {
        try writeFile(
            "<html><head><title>{{ title }}</title></head><body>{{ content }}</body></html>",
            at: "templates/post.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<html><body>{% for post in items %}<a href=\"{{ post.url }}\">{{ post.title }}</a>{% endfor %}</body></html>",
            at: "templates/blog-index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "---\ndate: 2026-01-02\ntitle: Second\ndescription: The second post.\n---\n\nSecond.",
            at: "content/blog/second.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "---\ndate: 2026-01-01\ntitle: First\ndescription: The first post.\n---\n\nFirst.",
            at: "content/blog/first.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
    }

    @Test("A collection page renders with the collection's template")
    func collectionPageRendersWithCollectionTemplate() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        try site.build()

        let post = try readFile(at: "build/blog/first/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(post?.contains("<title>First</title>") == true)
        #expect(post?.contains("<p>First.</p>") == true)
    }

    @Test("A page's declared template overrides the collection's template")
    func declaredTemplateOverridesCollectionTemplate() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)
        try writeFile(
            "<html><body>custom</body></html>",
            at: "templates/custom.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "---\ntemplate: custom\ntitle: Custom\n---\n\nBody.",
            at: "content/blog/custom.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        try site.build()

        let output = try readFile(at: "build/blog/custom/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("custom") == true)
    }

    @Test("Throws when a markdown page has no template and no collection")
    func throwsWhenMarkdownPageHasNoTemplateAndNoCollection() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "templates/home.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("---\ntitle: No Template\n---\nBody.", at: "content/index.md", relativeTo: virtualRoot, in: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .renderPages()

        #expect(throws: BuildError.self) {
            try site.build()
        }
    }

    @Test("Exposes the collection's pages as site.<name>")
    func exposesCollectionAsSiteVariable() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)
        try writeFile(
            "---\ntemplate: home\ntitle: Home\n---\n\n{% for post in site.blog %}{{ post.title }}{% endfor %}\n",
            at: "content/index.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<html><head><title>{{ title }}</title></head><body>{{ content }}</body></html>",
            at: "templates/home.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        try site.build()

        // Newest first: Second (2026-01-02) before First (2026-01-01).
        let output = try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("SecondFirst") == true)
    }

    @Test("Renders the collection's index with its pages")
    func rendersCollectionIndex() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        try site.build()

        let index = try readFile(at: "build/blog/index.html", relativeTo: virtualRoot, in: fileSystem)
        // Newest first: Second (2026-01-02) before First (2026-01-01).
        #expect(
            index?.contains("<a href=\"/blog/second\">Second</a><a href=\"/blog/first\">First</a>") == true
        )
    }

    @Test("Paginates the collection's index")
    func paginatesCollectionIndex() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)
        try writeFile(
            "---\ndate: 2026-01-03\ntitle: Third\n---\n\nThird.",
            at: "content/blog/third.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            <html><body>
            {% for post in items %}{{ post.title }}{% endfor %}
            {% if hasPrevious %}prev:{{ previousUrl }}{% endif %}
            {% if hasNext %}next:{{ nextUrl }}{% endif %}
            </body></html>
            """,
            at: "templates/blog-index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index", paginate: 2)
            .renderPages()

        try site.build()

        // Three posts, two per page: page 1 has the two newest, page 2 the
        // oldest.
        let page1 = try readFile(at: "build/blog/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(page1?.contains("ThirdSecond") == true)
        #expect(page1?.contains("next:/blog/page/2") == true)
        #expect(page1?.contains("prev:") == false)

        let page2 = try readFile(at: "build/blog/page/2/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(page2?.contains("First") == true)
        #expect(page2?.contains("prev:/blog") == true)
        #expect(page2?.contains("next:") == false)

        #expect(try readFile(at: "build/blog/page/3/index.html", relativeTo: virtualRoot, in: fileSystem) == nil)
    }

    @Test("A collection without paginate renders a single index page")
    func collectionWithoutPaginateRendersSingleIndex() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)
        try writeFile(
            "<html><body>total:{{ total }} count:{{ count }} number:{{ number }} pages:{{ pageCount }}</body></html>",
            at: "templates/blog-index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        try site.build()

        let index = try readFile(at: "build/blog/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(index?.contains("total:2 count:2 number:1 pages:1") == true)
    }

    @Test("A site can have several collections")
    func siteCanHaveSeveralCollections() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)
        try writeFile(
            "<html><body>gallery</body></html>",
            at: "templates/gallery-item.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "<html><body>{% for item in items %}{{ item.title }}{% endfor %}</body></html>",
            at: "templates/gallery-index.html",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            "---\ntitle: A Photo\n---\n\nA photo.",
            at: "content/gallery/photo.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .addCollection(name: "gallery", source: "gallery", template: "gallery-item", index: "gallery-index")
            .renderPages()

        try site.build()

        let blogIndex = try readFile(at: "build/blog/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(blogIndex?.contains("Second") == true)
        #expect(blogIndex?.contains("A Photo") == false)

        let galleryIndex = try readFile(at: "build/gallery/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(galleryIndex?.contains("A Photo") == true)
        #expect(galleryIndex?.contains("Second") == false)
    }

    @Test("Throws when the collection's directory does not exist")
    func throwsWhenCollectionDirectoryIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "no-such-directory", template: "post", index: "blog-index")
            .renderPages()

        #expect(throws: BuildError.missingPath(
            virtualRoot.appendingPathComponent("content/no-such-directory").path
        )) {
            try site.build()
        }
    }

    @Test("Throws when two collections share a name")
    func throwsWhenTwoCollectionsShareAName() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        #expect(throws: BuildError.missingConfiguration("two collections are named 'blog'")) {
            try site.build()
        }
    }

    @Test("Throws when a collection name collides with a built-in site variable")
    func throwsWhenCollectionNameCollidesWithBuiltIn() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "pages", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        #expect(throws: BuildError.self) {
            try site.build()
        }
    }

    @Test("Throws when a page sits at the collection's root")
    func throwsWhenAPageSitsAtTheCollectionRoot() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)
        try writeFile(
            "---\ntemplate: post\ntitle: Index\n---\n\nBody.",
            at: "content/blog/index.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        #expect(throws: BuildError.self) {
            try site.build()
        }
    }

    @Test("A localized collection lists the default-locale pages only")
    func localizedCollectionListsDefaultLocalePagesOnly() throws {
        let fileSystem = InMemoryFileSystem()
        try seedCollectionSite(fileSystem: fileSystem)
        try writeFile(
            "---\ndate: 2026-01-01\ntitle: Premier\n---\n\nPremier.",
            at: "content/blog/first.fr-fr.md",
            relativeTo: virtualRoot,
            in: fileSystem
        )

        let site = makeSite(fileSystem: fileSystem)
            .localize(defaultLocale: "en", locales: ["fr-fr"])
            .registerTemplates(in: "templates")
            .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index")
            .renderPages()

        try site.build()

        // The translation renders as an ordinary page…
        #expect(try readFile(at: "build/fr-fr/blog/first/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        // …but the collection lists the default-locale page only, and the
        // missing translation is not warned about.
        let index = try readFile(at: "build/blog/index.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(index?.contains("/blog/first") == true)
        #expect(index?.contains("fr-fr") == false)
        #expect(site.warnings.isEmpty)
    }
}
