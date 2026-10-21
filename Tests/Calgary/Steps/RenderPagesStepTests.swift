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

        #expect(try readFile(at: "build/blog/post.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/index.html", relativeTo: virtualRoot, in: fileSystem) != nil)
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

        let output = try readFile(at: "build/dated.html", relativeTo: virtualRoot, in: fileSystem)
        #expect(output?.contains("/dated.html / 2026-01-01") == true)
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

        let output = try readFile(at: "build/vars.html", relativeTo: virtualRoot, in: fileSystem)
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

        let output = try readFile(at: "build/hero-page.html", relativeTo: virtualRoot, in: fileSystem)
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
        #expect(try readFile(at: "build/nested/page.html", relativeTo: virtualRoot, in: fileSystem) != nil)
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

        #expect(try readFile(at: "build/nested/page.html", relativeTo: virtualRoot, in: fileSystem) != nil)
        #expect(try readFile(at: "build/nested/page.html.html", relativeTo: virtualRoot, in: fileSystem) == nil)
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
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"en\" href=\"/index.html\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"fr-fr\" href=\"/fr-fr/index.html\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"de\" href=\"/de/index.html\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"x-default\" href=\"/index.html\">") == true)

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

        #expect(try readFile(at: "build/index.fr-fr.html", relativeTo: virtualRoot, in: fileSystem) != nil)
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
        #expect(output?.contains("fr-fr / en / /fr-fr/index.html") == true)
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
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"en\" href=\"/index.html\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"fr-fr\" href=\"/fr-fr/index.html\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"x-default\" href=\"/index.html\">") == true)
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
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"en\" href=\"/index.html\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"fr-fr\" href=\"/fr-fr/index.html\">") == true)
        #expect(output?.contains("<link rel=\"alternate\" hreflang=\"x-default\" href=\"/index.html\">") == true)
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
}
