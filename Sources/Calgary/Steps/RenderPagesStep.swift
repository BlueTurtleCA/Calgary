//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// RenderPagesStep.swift
//

import Foundation

/// A build step that renders pages into HTML.
///
/// Markdown pages are markdown files with YAML frontmatter declaring their
/// template and variables. The page's body is rendered — includes resolved,
/// variables interpolated, markdown converted to HTML — and injected into
/// the template as `{{ content }}`.
///
/// HTML pages are standalone documents: they are rendered by the template
/// engine (includes resolved, variables interpolated) but not converted from
/// markdown or wrapped in a template. Their frontmatter is optional.
///
/// The output path mirrors the source path: `content/blog/post.md` becomes
/// `build/blog/post.html`, and `content/about.html` becomes
/// `build/about.html`.
///
/// When the site is localized, a page whose file name ends in `.<locale>.md`
/// or `.<locale>.html` for a declared non-default locale is a translation:
/// it is written under a subfolder named after the locale, with the locale
/// suffix removed: `content/blog/post.fr-fr.md` becomes
/// `build/fr-fr/blog/post.html`.
struct RenderPagesStep: BuildStep {
    /// The glob of page files to render, relative to the source directory.
    let glob: String

    init(glob: String = "**/*.{md,html}") {
        self.glob = glob
    }

    var name: String {
        "Render pages matching '\(glob)'"
    }

    func run(site: Site) throws {
        if let componentsDirectory = site.componentsDirectory {
            let componentsURL = site.root.appendingPathComponent(componentsDirectory)
            guard site.fileSystem.fileExists(atPath: componentsURL.path) else {
                throw BuildError.missingPath(componentsURL.path)
            }
        }
        let sourceURL = site.sourceDirectory
        guard site.fileSystem.fileExists(atPath: sourceURL.path) else {
            throw BuildError.missingPath(sourceURL.path)
        }

        let engine = TemplateEngine()
        let resolver = ComponentResolver(root: site.root, fileSystem: site.fileSystem)
        let renderer = MarkdownRenderer()
        let stringTable = try loadStringTable(for: site)

        let pages = try pageFiles(in: sourceURL, glob: glob, fileSystem: site.fileSystem)

        // Markdown pages render into a registered template, and a
        // collection's index renders from one, so templates are required
        // when the site has any markdown pages or any collections.
        var templatesURL: URL?
        if pages.contains(where: { !$0.path.hasSuffix(".html") }) || !site.collections.isEmpty {
            guard let templatesDirectory = site.templatesDirectory else {
                throw BuildError.missingConfiguration("renderPages requires registerTemplates(in:)")
            }
            let url = site.root.appendingPathComponent(templatesDirectory)
            guard site.fileSystem.fileExists(atPath: url.path) else {
                throw BuildError.missingPath(url.path)
            }
            templatesURL = url
        }

        // Collect every page's frontmatter up front so each page can see the
        // site's pages as {{ site.pages }} and the site's collections as
        // {{ site.<name> }} while it renders.
        let pagesVariable = try Self.pageCollection(for: pages, site: site)
        try Self.validate(site.collections)
        try Self.validateOutputPaths(for: pages, site: site)
        let collections = try Self.collectionData(for: site.collections, pages: pages, site: site)
        let defaultLocale = site.localization?.defaultLocale ?? "default"
        let locales = site.localization?.locales ?? ["default"]
        var collectionsVariablesByLocale: [String: [String: Variable]] = [:]
        for locale in locales {
            var byCollection: [String: Variable] = [:]
            for data in collections {
                byCollection[data.collection.name] = .list(data.entriesByLocale[locale] ?? [])
            }
            collectionsVariablesByLocale[locale] = byCollection
        }

        for pageURL in pages {
            try renderPage(
                at: pageURL,
                site: site,
                templatesURL: templatesURL,
                engine: engine,
                resolver: resolver,
                renderer: renderer,
                stringTable: stringTable,
                pagesVariable: pagesVariable,
                collectionsVariablesByLocale: collectionsVariablesByLocale
            )
        }

        // The collection indexes render after the pages, so the posts they
        // link to exist in the output. Each locale's index lists that locale's
        // pages and renders under /<locale>/; a locale with no translated
        // pages is skipped with a warning.
        for data in collections {
            for locale in locales {
                let entries = data.entriesByLocale[locale] ?? []
                if entries.isEmpty, locale != defaultLocale {
                    site.warn(
                        "no '\(locale)' translations of the '\(data.collection.name)' collection; '\(locale)/\(data.collection.source)/index.html' not rendered"
                    )
                    continue
                }
                let alternatesLocales = locales.filter { entry in
                    (data.entriesByLocale[entry] ?? []).isEmpty == false || entry == defaultLocale
                }
                try renderCollectionIndex(
                    for: data.collection,
                    entries: entries,
                    locale: locale,
                    alternatesLocales: alternatesLocales,
                    site: site,
                    templatesURL: templatesURL,
                    engine: engine,
                    resolver: resolver,
                    stringTable: stringTable,
                    pagesVariable: pagesVariable,
                    collectionsVariablesByLocale: collectionsVariablesByLocale
                )
            }
        }
    }

    // MARK: Page rendering

    private func renderPage(
        at pageURL: URL,
        localeOverride: String? = nil,
        site: Site,
        templatesURL: URL?,
        engine: TemplateEngine,
        resolver: ComponentResolver,
        renderer: MarkdownRenderer,
        stringTable: StringTable?,
        pagesVariable: Variable,
        collectionsVariablesByLocale: [String: [String: Variable]]
    ) throws {
        let data = try site.fileSystem.read(contentsOf: pageURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        let isHTMLPage = pageURL.path.hasSuffix(".html")
        let page = isHTMLPage ? try Frontmatter.parseHTML(text) : try Frontmatter.parse(text)

        let relative = site.fileSystem.relativePath(of: pageURL, to: site.sourceDirectory)
        let locale = localeOverride ?? Self.locale(of: relative, in: site.localization)
        let defaultLocale = site.localization?.defaultLocale ?? "default"
        let urlPath = Self.urlPath(for: relative, slug: page.slug, locale: locale, defaultLocale: defaultLocale)
        let outputRelative = PageURL.outputPath(forURLPath: urlPath)
        let collectionsVariable = collectionsVariablesByLocale[locale] ?? [:]

        var variables = builtInVariables(
            for: site,
            page: page,
            locale: locale,
            defaultLocale: defaultLocale,
            urlPath: urlPath,
            sourceRelative: relative,
            pagesVariable: pagesVariable,
            collectionsVariable: collectionsVariable
        )
        .merged(with: page.variables)

        if let stringTable {
            variables = variables.merged(with: stringTable.variables(for: locale))
        }

        // Render the body: resolve includes and interpolate variables.
        // Markdown pages are then converted to HTML; HTML pages are already
        // HTML.
        let bodyWithIncludes = try engine.render(page.body, variables: variables, resolver: resolver)
        let bodyHTML = isHTMLPage ? bodyWithIncludes : renderer.render(bodyWithIncludes)

        let html: String
        if isHTMLPage {
            html = bodyHTML
        } else {
            // A markdown page renders with its declared template, falling
            // back to the template of the collection it belongs to.
            let templateName = page.template ?? Self.collection(for: relative, in: site.collections)?.template
            guard let templateName else {
                throw FrontmatterError.missingTemplate
            }
            guard let templatesURL else {
                throw BuildError.missingConfiguration("renderPages requires registerTemplates(in:)")
            }
            variables = variables.merged(with: Variables(["content": .string(bodyHTML)]))
            let template = try loadTemplate(named: templateName, in: templatesURL, fileSystem: site.fileSystem)
            html = try engine.render(template, variables: variables, resolver: resolver)
        }

        let outputURL = site.outputDirectory.appendingPathComponent(outputRelative)
        try site.fileSystem.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try site.fileSystem.write(Data(html.utf8), to: outputURL)

        // A default-locale HTML page is locale-neutral content: render it for
        // every declared locale that has no explicit translation file, so its
        // strings and variables pick up that locale. A default-locale markdown
        // page needs an explicit translation file; warn when one is missing.
        if locale == defaultLocale, let localization = site.localization {
            let base = Self.baseName(of: relative)
            // Collection pages are independent pages: a blog does not
            // translate every post, so a missing translation is not warned
            // about.
            let inCollection = Self.collection(for: relative, in: site.collections) != nil
            for otherLocale in localization.locales where otherLocale != defaultLocale {
                guard !Self.hasTranslation(
                    of: base,
                    in: otherLocale,
                    sourceDirectory: site.sourceDirectory,
                    fileSystem: site.fileSystem
                ) else { continue }
                if isHTMLPage {
                    try renderPage(
                        at: pageURL,
                        localeOverride: otherLocale,
                        site: site,
                        templatesURL: templatesURL,
                        engine: engine,
                        resolver: resolver,
                        renderer: renderer,
                        stringTable: stringTable,
                        pagesVariable: pagesVariable,
                        collectionsVariablesByLocale: collectionsVariablesByLocale
                    )
                } else if !inCollection {
                    site.warn(
                        "no '\(otherLocale)' version of '\(relative)' found; '\(otherLocale)/\(base).html' was not rendered"
                    )
                }
            }
        }
    }

    private func builtInVariables(
        for site: Site,
        page: Page,
        locale: String,
        defaultLocale: String,
        urlPath: String,
        sourceRelative: String,
        pagesVariable: Variable,
        collectionsVariable: [String: Variable]
    ) -> Variables {
        var pageValues: [String: Variable] = ["url": .string(PageURL.url(forURLPath: urlPath))]
        if let date = page.date {
            pageValues["date"] = .string(date)
        }
        if let baseUrl = site.baseUrl {
            pageValues["canonical"] = .string(PageURL.absolute(forURLPath: urlPath, baseUrl: baseUrl))
        }

        let variables = siteVariables(
            for: site,
            pagesVariable: pagesVariable,
            collectionsVariable: collectionsVariable
        )

        if site.localization != nil {
            pageValues["locale"] = .string(locale)
            if let alternates = alternateLinks(
                for: site,
                sourceRelative: sourceRelative,
                locale: locale,
                defaultLocale: defaultLocale
            ) {
                pageValues["alternates"] = .string(alternates)
            }
        }

        return variables.merged(with: Variables(["page": .map(pageValues)]))
    }

    /// The `site` namespace: the built-ins (`name`, `year`, `pages`), the
    /// site's `templateVariables`, the site's collections (each exposed as
    /// `site.<name>`), and (when localized) `defaultLocale`.
    private func siteVariables(
        for site: Site,
        pagesVariable: Variable,
        collectionsVariable: [String: Variable]
    ) -> Variables {
        var siteValues: [String: Variable] = [
            "name": .string(site.name),
            "year": .integer(Calendar.current.component(.year, from: .now)),
        ]
        siteValues["pages"] = pagesVariable
        for (key, value) in site.templateVariables {
            siteValues[key] = value
        }
        for (key, value) in collectionsVariable {
            siteValues[key] = value
        }
        if let localization = site.localization {
            siteValues["defaultLocale"] = .string(localization.defaultLocale)
        }
        return Variables(["site": .map(siteValues)])
    }

    private func loadTemplate(named name: String, in directory: URL, fileSystem: any FileSystem) throws -> String {
        let base = directory.appendingPathComponent(name)
        let candidates: [URL]
        if name.hasSuffix(".html") {
            candidates = [base]
        } else {
            candidates = [base.appendingPathExtension("html"), base]
        }
        for candidate in candidates where fileSystem.fileExists(atPath: candidate.path) {
            let data = try fileSystem.read(contentsOf: candidate)
            return String(data: data, encoding: .utf8) ?? ""
        }
        throw TemplateError.templateNotFound(name)
    }

    // MARK: Localization

    /// Determines a page's locale from its path, relative to the source
    /// directory.
    ///
    /// A page is a translation when its file name ends in `.<locale>.md` or
    /// `.<locale>.html` for a declared non-default locale; otherwise it
    /// belongs to the default locale.
    private static func locale(of relative: String, in localization: Localization?) -> String {
        guard let localization else { return "default" }
        let fileName = relative.split(separator: "/").last.map(String.init) ?? relative
        let base = Self.baseName(of: fileName)
        for locale in localization.locales where locale != localization.defaultLocale {
            if base.hasSuffix("." + locale) {
                return locale
            }
        }
        return localization.defaultLocale
    }

    /// Strips a page's extension from a file name or relative path:
    /// `post.md` and `post.html` both become `post`.
    private static func baseName(of path: String) -> String {
        if path.hasSuffix(".md") {
            return String(path.dropLast(3))
        }
        if path.hasSuffix(".html") {
            return String(path.dropLast(5))
        }
        return path
    }

    /// Whether an explicit translation file exists for a page base in a
    /// locale: either `<base>.<locale>.md` or `<base>.<locale>.html`.
    private static func hasTranslation(
        of base: String,
        in locale: String,
        sourceDirectory: URL,
        fileSystem: any FileSystem
    ) -> Bool {
        for extensionName in ["md", "html"] {
            let fileName = "\(base).\(locale).\(extensionName)"
            if fileSystem.fileExists(atPath: sourceDirectory.appendingPathComponent(fileName).path) {
                return true
            }
        }
        return false
    }

    /// The page's file name without its extension and locale suffix:
    /// `blog/hello-world.fr-fr.md` and `blog/hello-world.md` both become
    /// `hello-world`.
    private static func fileNameBase(of relative: String, locale: String, defaultLocale: String) -> String {
        var name = relative.split(separator: "/").last.map(String.init) ?? relative
        name = Self.baseName(of: name)
        if locale != defaultLocale, name.hasSuffix("." + locale) {
            name = String(name.dropLast(locale.count + 1))
        }
        return name
    }

    /// The page's URL path in the default locale: its directory plus its slug,
    /// with a trailing `index` component dropped, so a page named `index` is
    /// its directory's index.
    ///
    /// The slug is the page's `slug:` frontmatter value, or its file name
    /// (without extension and locale suffix) when none is declared. It is
    /// relative to the page's directory, so a post in `content/blog` with
    /// `slug: 2026-01-05/hello-world` has the URL path
    /// `blog/2026-01-05/hello-world`.
    private static func defaultURLPath(for relative: String, slug: String?, locale: String, defaultLocale: String) -> String {
        let directory: String
        if let slashIndex = relative.lastIndex(of: "/") {
            directory = String(relative[..<slashIndex])
        } else {
            directory = ""
        }
        let base = Self.fileNameBase(of: relative, locale: locale, defaultLocale: defaultLocale)
        let effectiveSlug = slug ?? base
        var path = directory.isEmpty ? effectiveSlug : directory + "/" + effectiveSlug
        if path.split(separator: "/").last.map(String.init) == "index" {
            path = path.lastIndex(of: "/").map { String(path[..<$0]) } ?? ""
        }
        return path
    }

    /// The page's URL path in a locale: the default-locale URL path, prefixed
    /// with the locale when it is not the default, so `blog/hello-world` in
    /// `fr-fr` is `fr-fr/blog/hello-world`.
    private static func urlPath(for relative: String, slug: String?, locale: String, defaultLocale: String) -> String {
        let defaultPath = Self.defaultURLPath(for: relative, slug: slug, locale: locale, defaultLocale: defaultLocale)
        guard locale != defaultLocale else { return defaultPath }
        return defaultPath.isEmpty ? locale : locale + "/" + defaultPath
    }

    /// The output file path, relative to the output directory, for a page:
    /// `index.html` for the root, otherwise `<url path>/index.html`. So
    /// `blog/post.md` becomes `blog/post/index.html`, and
    /// `blog/post.fr-fr.md` becomes `fr-fr/blog/post/index.html`.
    private static func outputPath(for relative: String, slug: String?, locale: String, defaultLocale: String) -> String {
        PageURL.outputPath(forURLPath: Self.urlPath(for: relative, slug: slug, locale: locale, defaultLocale: defaultLocale))
    }

    /// Builds the `<link rel="alternate" hreflang="…">` tags for a page: one
    /// per declared locale that has a translation of the page, plus an
    /// `x-default` tag pointing at the default locale. Returns `nil` when the
    /// site is not localized.
    private func alternateLinks(
        for site: Site,
        sourceRelative: String,
        locale: String,
        defaultLocale: String
    ) -> String? {
        guard let localization = site.localization else { return nil }

        // The page's path without its extension and any locale suffix.
        var base = Self.baseName(of: sourceRelative)
        if locale != defaultLocale {
            let suffix = "." + locale
            if base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
            }
        }

        // A default-locale HTML page renders for every declared locale, so it
        // counts as a page for each locale even without an explicit
        // translation file.
        let defaultHTMLPage = site.fileSystem.fileExists(
            atPath: site.sourceDirectory.appendingPathComponent(base + ".html").path
        )

        var links: [String] = []
        var defaultURL: String?
        for alternate in localization.locales {
            let sourceFiles: [String]
            if alternate == defaultLocale {
                sourceFiles = [base + ".md", base + ".html"]
            } else {
                sourceFiles = [base + "." + alternate + ".md", base + "." + alternate + ".html"]
            }
            let url = Self.alternateURL(forBase: base, in: alternate, defaultLocale: defaultLocale, site: site)
            let hasExplicitFile = sourceFiles.contains(where: {
                site.fileSystem.fileExists(
                    atPath: site.sourceDirectory.appendingPathComponent($0).path
                )
            })
            guard hasExplicitFile || (alternate != defaultLocale && defaultHTMLPage) else { continue }
            links.append("<link rel=\"alternate\" hreflang=\"\(alternate)\" href=\"\(url)\">")
            if alternate == defaultLocale {
                defaultURL = url
            }
        }
        if let defaultURL {
            links.append("<link rel=\"alternate\" hreflang=\"x-default\" href=\"\(defaultURL)\">")
        }
        return links.joined(separator: "\n")
    }

    /// The URL of a page's base in a locale, accounting for the slug declared
    /// in that locale's source file. An explicit translation is preferred,
    /// then the default-locale file (a default-locale HTML page renders for
    /// every declared locale).
    private static func alternateURL(
        forBase base: String,
        in locale: String,
        defaultLocale: String,
        site: Site
    ) -> String {
        let sourceFiles: [String]
        if locale == defaultLocale {
            sourceFiles = [base + ".md", base + ".html"]
        } else {
            sourceFiles = [base + "." + locale + ".md", base + "." + locale + ".html", base + ".md", base + ".html"]
        }
        for fileName in sourceFiles {
            let url = site.sourceDirectory.appendingPathComponent(fileName)
            guard site.fileSystem.fileExists(atPath: url.path) else { continue }
            let data = (try? site.fileSystem.read(contentsOf: url)) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? ""
            let page = fileName.hasSuffix(".html")
                ? (try? Frontmatter.parseHTML(text))
                : (try? Frontmatter.parse(text))
            let urlPath = Self.urlPath(for: fileName, slug: page?.slug, locale: locale, defaultLocale: defaultLocale)
            return PageURL.url(forURLPath: urlPath)
        }
        // No source file found: fall back to the file-name slug.
        let urlPath = Self.urlPath(for: base + ".md", slug: nil, locale: locale, defaultLocale: defaultLocale)
        return PageURL.url(forURLPath: urlPath)
    }

    // MARK: Strings

    /// Loads the site's string table, if a strings source is configured.
    ///
    /// The source is either a directory of per-locale YAML files or an Xcode
    /// string catalog (`.xcstrings`) file.
    private func loadStringTable(for site: Site) throws -> StringTable? {
        guard let localization = site.localization, let stringsPath = localization.stringsPath else {
            return nil
        }
        let path = site.root.appendingPathComponent(stringsPath)
        guard site.fileSystem.fileExists(atPath: path.path) else {
            throw BuildError.missingPath(path.path)
        }
        var table = StringTable(
            defaultLocale: localization.defaultLocale,
            fileSystem: site.fileSystem
        )
        if site.fileSystem.isDirectory(atPath: path.path) {
            try table.loadYAMLFiles(in: path)
        } else {
            guard path.path.hasSuffix(".xcstrings") else {
                throw BuildError.unexpectedPathType(
                    path: path.path,
                    expected: "a directory of YAML string files or a .xcstrings catalog"
                )
            }
            try table.loadCatalog(at: path)
        }
        return table
    }

    // MARK: Page discovery

    private func pageFiles(in directory: URL, glob: String, fileSystem: any FileSystem) throws -> [URL] {
        try fileSystem.files(in: directory).filter {
            Glob.matches(glob, path: fileSystem.relativePath(of: $0, to: directory))
        }
    }

    // MARK: Page collection

    /// Builds the `site.pages` variable: a list with one entry per page, each
    /// a map of the page's frontmatter variables with the canonical `title`,
    /// `url`, `locale`, and (when declared) `date` layered on top.
    private static func pageCollection(for pages: [URL], site: Site) throws -> Variable {
        let fileSystem = site.fileSystem
        var entries: [Variable] = []
        for pageURL in pages {
            let page = try Self.parsedPage(at: pageURL, fileSystem: fileSystem)
            let relative = fileSystem.relativePath(of: pageURL, to: site.sourceDirectory)
            entries.append(.map(Self.entry(for: page, relative: relative, site: site)))
        }
        return .list(entries)
    }

    /// Reads and parses a page file.
    private static func parsedPage(at pageURL: URL, fileSystem: any FileSystem) throws -> Page {
        let data = try fileSystem.read(contentsOf: pageURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        let isHTMLPage = pageURL.path.hasSuffix(".html")
        return isHTMLPage ? try Frontmatter.parseHTML(text) : try Frontmatter.parse(text)
    }

    /// Builds one entry of `site.pages` (and of a collection's list): the
    /// page's frontmatter variables, with the canonical `title`, `url`,
    /// `locale`, and (when declared) `date` layered on top.
    private static func entry(for page: Page, relative: String, site: Site) -> [String: Variable] {
        let defaultLocale = site.localization?.defaultLocale ?? "default"
        let locale = Self.locale(of: relative, in: site.localization)
        let urlPath = Self.urlPath(for: relative, slug: page.slug, locale: locale, defaultLocale: defaultLocale)
        var entry: [String: Variable] = page.variables.values
        entry["title"] = .string(
            page.variables["title"]?.stringValue
                ?? Self.fallbackTitle(for: relative, locale: locale, defaultLocale: defaultLocale)
        )
        entry["url"] = .string(PageURL.url(forURLPath: urlPath))
        entry["locale"] = .string(locale)
        if let date = page.date {
            entry["date"] = .string(date)
        }
        return entry
    }

    /// A page's title when its frontmatter declares none: the file name
    /// without its extension and locale suffix.
    private static func fallbackTitle(for relative: String, locale: String, defaultLocale: String) -> String {
        Self.fileNameBase(of: relative, locale: locale, defaultLocale: defaultLocale)
    }

    // MARK: Collections

    /// The data for a site's collections, built before any page renders so
    /// every page can see the collections as `{{ site.<name> }}`.
    private struct CollectionData {
        let collection: SiteCollection
        /// The collection's pages as template variables per locale, newest
        /// first: the default-locale pages under the default locale and each
        /// translation under its own locale. A locale with no translated pages
        /// lists an empty list.
        let entriesByLocale: [String: [Variable]]
    }

    /// Validates the site's collections: names must be unique and must not
    /// collide with a built-in `site` variable, and a page size must be
    /// positive.
    private static func validate(_ collections: [SiteCollection]) throws {
        let builtIns: Set<String> = ["name", "year", "pages", "defaultLocale"]
        var seen: Set<String> = []
        for collection in collections {
            guard !builtIns.contains(collection.name) else {
                throw BuildError.missingConfiguration(
                    "the collection name '\(collection.name)' collides with a built-in site variable"
                )
            }
            guard seen.insert(collection.name).inserted else {
                throw BuildError.missingConfiguration("two collections are named '\(collection.name)'")
            }
            if let paginate = collection.paginate, paginate < 1 {
                throw BuildError.missingConfiguration(
                    "collection '\(collection.name)' paginates by \(paginate); the page size must be at least 1"
                )
            }
        }
    }

    /// Validates the pages' output paths: a declared slug must not be empty,
    /// malformed, or contain a `..` segment, and two pages must not build to
    /// the same file.
    private static func validateOutputPaths(for pages: [URL], site: Site) throws {
        let fileSystem = site.fileSystem
        let defaultLocale = site.localization?.defaultLocale ?? "default"
        var seen: [String: String] = [:]
        for pageURL in pages {
            let relative = fileSystem.relativePath(of: pageURL, to: site.sourceDirectory)
            let page = try parsedPage(at: pageURL, fileSystem: fileSystem)
            if let slug = page.slug {
                let segments = slug.components(separatedBy: "/")
                if segments.contains("..") {
                    throw BuildError.missingConfiguration(
                        "the slug '\(slug)' in '\(relative)' must not contain '..'"
                    )
                }
                if segments.contains(where: { $0.isEmpty }) {
                    throw BuildError.missingConfiguration(
                        "the slug '\(slug)' in '\(relative)' is empty or malformed"
                    )
                }
            }
            let locale = Self.locale(of: relative, in: site.localization)
            let outputRelative = Self.outputPath(for: relative, slug: page.slug, locale: locale, defaultLocale: defaultLocale)
            if let existing = seen[outputRelative] {
                throw BuildError.missingConfiguration(
                    "'\(relative)' and '\(existing)' both build to '\(outputRelative)'"
                )
            }
            seen[outputRelative] = relative
        }
    }

    /// Builds the data for each of the site's collections: its pages, as
    /// template variables, sorted by `date` descending (pages without a
    /// `date` last, then by file name).
    ///
    /// A page belongs to a collection when its source path is under the
    /// collection's directory. Each declared locale lists the collection's
    /// pages in that locale: the default locale lists the default-locale
    /// pages, and other locales list their translations.
    private static func collectionData(
        for collections: [SiteCollection],
        pages: [URL],
        site: Site
    ) throws -> [CollectionData] {
        let fileSystem = site.fileSystem
        let locales = site.localization?.locales ?? ["default"]
        var data: [CollectionData] = []
        for collection in collections {
            let sourceDirectory = site.sourceDirectory.appendingPathComponent(collection.source)
            guard fileSystem.fileExists(atPath: sourceDirectory.path) else {
                throw BuildError.missingPath(sourceDirectory.path)
            }
            // A page at the collection's root would be overwritten by the
            // generated index.
            for indexPage in ["index.md", "index.html"] {
                let path = sourceDirectory.appendingPathComponent(indexPage)
                if fileSystem.fileExists(atPath: path.path) {
                    throw BuildError.missingConfiguration(
                        "collection '\(collection.name)' generates its index at '\(collection.source)/index.html', so there cannot be a page at '\(collection.source)/\(indexPage)'"
                    )
                }
            }

            var dated: [String: [(date: String, name: String, entry: [String: Variable])]] = [:]
            var undated: [String: [(name: String, entry: [String: Variable])]] = [:]
            for pageURL in pages {
                let relative = fileSystem.relativePath(of: pageURL, to: site.sourceDirectory)
                guard relative.hasPrefix(collection.source + "/") else { continue }
                let page = try parsedPage(at: pageURL, fileSystem: fileSystem)
                let locale = Self.locale(of: relative, in: site.localization)
                guard locales.contains(locale) else { continue }
                let entry = Self.entry(for: page, relative: relative, site: site)
                let name = relative.split(separator: "/").last.map(String.init) ?? relative
                if let date = page.date {
                    dated[locale, default: []].append((date: date, name: name, entry: entry))
                } else {
                    undated[locale, default: []].append((name: name, entry: entry))
                }
            }
            var entriesByLocale: [String: [Variable]] = [:]
            for locale in locales {
                let sortedDated = (dated[locale] ?? []).sorted {
                    $0.date == $1.date ? $0.name < $1.name : $0.date > $1.date
                }
                let sortedUndated = (undated[locale] ?? []).sorted { $0.name < $1.name }
                entriesByLocale[locale] = sortedDated.map { .map($0.entry) } + sortedUndated.map { .map($0.entry) }
            }
            data.append(CollectionData(collection: collection, entriesByLocale: entriesByLocale))
        }
        return data
    }

    /// The collection a page belongs to, if any: the first collection whose
    /// directory contains the page's source path.
    private static func collection(for relative: String, in collections: [SiteCollection]) -> SiteCollection? {
        collections.first { relative.hasPrefix($0.source + "/") }
    }

    /// Renders a collection's index for one locale: one page per chunk of the
    /// locale's entries, from the collection's index template. The default
    /// locale renders at `<source>/index.html`; other locales render under a
    /// subfolder named after the locale (`fr-fr/blog/index.html`).
    private func renderCollectionIndex(
        for collection: SiteCollection,
        entries: [Variable],
        locale: String,
        alternatesLocales: [String],
        site: Site,
        templatesURL: URL?,
        engine: TemplateEngine,
        resolver: ComponentResolver,
        stringTable: StringTable?,
        pagesVariable: Variable,
        collectionsVariablesByLocale: [String: [String: Variable]]
    ) throws {
        guard let templatesURL else {
            throw BuildError.missingConfiguration("renderPages requires registerTemplates(in:)")
        }
        let defaultLocale = site.localization?.defaultLocale ?? "default"
        let pageCount: Int
        if let paginate = collection.paginate {
            pageCount = max(1, (entries.count + paginate - 1) / paginate)
        } else {
            pageCount = 1
        }
        let template = try loadTemplate(named: collection.index, in: templatesURL, fileSystem: site.fileSystem)
        let prefix = locale == defaultLocale ? "" : locale + "/"
        let collectionsVariable = collectionsVariablesByLocale[locale] ?? [:]

        for number in 1...pageCount {
            let perPage = collection.paginate ?? entries.count
            let start = (number - 1) * perPage
            let items = Array(entries[start..<min(start + perPage, entries.count)])
            let outputRelative = number == 1
                ? prefix + collection.source + "/index.html"
                : "\(prefix)\(collection.source)/page/\(number)/index.html"

            var pageValues: [String: Variable] = ["url": .string("/" + PageURL.path(for: outputRelative))]
            if let baseUrl = site.baseUrl {
                pageValues["canonical"] = .string(PageURL.absolute(for: outputRelative, baseUrl: baseUrl))
            }
            if site.localization != nil {
                pageValues["locale"] = .string(locale)
                if let alternates = indexAlternates(
                    locale: locale,
                    defaultLocale: defaultLocale,
                    source: collection.source,
                    pageNumber: number,
                    locales: alternatesLocales,
                    site: site
                ) {
                    pageValues["alternates"] = .string(alternates)
                }
            }

            var variables = siteVariables(
                for: site,
                pagesVariable: pagesVariable,
                collectionsVariable: collectionsVariable
            )
            .merged(with: Variables(["page": .map(pageValues)]))
            if let stringTable {
                variables = variables.merged(with: stringTable.variables(for: locale))
            }
            variables = variables.merged(with: Variables([
                "items": .list(items),
                "total": .integer(entries.count),
                "count": .integer(items.count),
                "number": .integer(number),
                "pageCount": .integer(pageCount),
                "hasPrevious": .boolean(number > 1),
                "hasNext": .boolean(number < pageCount),
            ]))
            if number > 1 {
                let previous = number - 1 == 1
                    ? collection.source + "/index.html"
                    : "\(collection.source)/page/\(number - 1)/index.html"
                variables = variables.merged(
                    with: Variables(["previousUrl": .string("/" + PageURL.path(for: prefix + previous))])
                )
            }
            if number < pageCount {
                let next = "\(collection.source)/page/\(number + 1)/index.html"
                variables = variables.merged(
                    with: Variables(["nextUrl": .string("/" + PageURL.path(for: prefix + next))])
                )
            }

            let html = try engine.render(template, variables: variables, resolver: resolver)
            let outputURL = site.outputDirectory.appendingPathComponent(outputRelative)
            try site.fileSystem.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try site.fileSystem.write(Data(html.utf8), to: outputURL)
        }
    }

    /// The `<link rel="alternate" hreflang="…">` tags for a collection index
    /// page: one per declared locale whose index renders for this page (the
    /// default, plus any locale with at least one translated page), plus an
    /// `x-default` tag pointing at the default-locale index. Returns `nil`
    /// when the site is not localized.
    private func indexAlternates(
        locale: String,
        defaultLocale: String,
        source: String,
        pageNumber: Int,
        locales: [String],
        site: Site
    ) -> String? {
        guard let localization = site.localization else { return nil }
        var links: [String] = []
        var defaultURL: String?
        for alternate in localization.locales where locales.contains(alternate) {
            let prefix = alternate == defaultLocale ? "" : alternate + "/"
            let path = pageNumber == 1
                ? prefix + source
                : prefix + "\(source)/page/\(pageNumber)"
            let url = PageURL.url(forURLPath: path)
            links.append("<link rel=\"alternate\" hreflang=\"\(alternate)\" href=\"\(url)\">")
            if alternate == defaultLocale {
                defaultURL = url
            }
        }
        if let defaultURL {
            links.append("<link rel=\"alternate\" hreflang=\"x-default\" href=\"\(defaultURL)\">")
        }
        return links.isEmpty ? nil : links.joined(separator: "\n")
    }
}
