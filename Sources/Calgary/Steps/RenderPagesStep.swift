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

        // Markdown pages render into a registered template, so templates are
        // required only when the site has any of them.
        var templatesURL: URL?
        if pages.contains(where: { !$0.path.hasSuffix(".html") }) {
            guard let templatesDirectory = site.templatesDirectory else {
                throw BuildError.missingConfiguration("renderPages requires registerTemplates(in:)")
            }
            let url = site.root.appendingPathComponent(templatesDirectory)
            guard site.fileSystem.fileExists(atPath: url.path) else {
                throw BuildError.missingPath(url.path)
            }
            templatesURL = url
        }

        for pageURL in pages {
            try renderPage(
                at: pageURL,
                site: site,
                templatesURL: templatesURL,
                engine: engine,
                resolver: resolver,
                renderer: renderer,
                stringTable: stringTable
            )
        }
    }

    // MARK: Page rendering

    private func renderPage(
        at pageURL: URL,
        site: Site,
        templatesURL: URL?,
        engine: TemplateEngine,
        resolver: ComponentResolver,
        renderer: MarkdownRenderer,
        stringTable: StringTable?
    ) throws {
        let data = try site.fileSystem.read(contentsOf: pageURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        let isHTMLPage = pageURL.path.hasSuffix(".html")
        let page = isHTMLPage ? try Frontmatter.parseHTML(text) : try Frontmatter.parse(text)

        let relative = relativePath(of: pageURL, to: site.sourceDirectory)
        let locale = Self.locale(of: relative, in: site.localization)
        let defaultLocale = site.localization?.defaultLocale ?? "default"
        let outputRelative = Self.outputPath(for: relative, locale: locale, defaultLocale: defaultLocale)

        var variables = builtInVariables(
            for: site,
            page: page,
            locale: locale,
            defaultLocale: defaultLocale,
            outputRelative: outputRelative,
            sourceRelative: relative
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
        if let templateName = page.template {
            guard let templatesURL else {
                throw BuildError.missingConfiguration("renderPages requires registerTemplates(in:)")
            }
            variables = variables.merged(with: Variables(["content": .string(bodyHTML)]))
            let template = try loadTemplate(named: templateName, in: templatesURL, fileSystem: site.fileSystem)
            html = try engine.render(template, variables: variables, resolver: resolver)
        } else {
            html = bodyHTML
        }

        let outputURL = site.outputDirectory.appendingPathComponent(outputRelative)
        try site.fileSystem.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try site.fileSystem.write(Data(html.utf8), to: outputURL)
    }

    private func builtInVariables(
        for site: Site,
        page: Page,
        locale: String,
        defaultLocale: String,
        outputRelative: String,
        sourceRelative: String
    ) -> Variables {
        var pageValues: [String: Variable] = ["url": .string("/" + outputRelative)]
        if let date = page.date {
            pageValues["date"] = .string(date)
        }
        var siteValues: [String: Variable] = ["name": .string(site.name)]

        if site.localization != nil {
            pageValues["locale"] = .string(locale)
            siteValues["defaultLocale"] = .string(defaultLocale)
            if let alternates = alternateLinks(
                for: site,
                sourceRelative: sourceRelative,
                locale: locale,
                defaultLocale: defaultLocale
            ) {
                pageValues["alternates"] = .string(alternates)
            }
        }

        return Variables([
            "site": .map(siteValues),
            "page": .map(pageValues),
        ])
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

    /// The output path, relative to the output directory, for a page.
    ///
    /// Default-locale pages mirror their source path: `blog/post.md` becomes
    /// `blog/post.html`, and `about.html` stays `about.html`. Translations
    /// are written under a subfolder named after the locale, with the locale
    /// suffix removed: `blog/post.fr-fr.md` becomes `fr-fr/blog/post.html`.
    private static func outputPath(for relative: String, locale: String, defaultLocale: String) -> String {
        if locale != defaultLocale {
            for ext in [".md", ".html"] {
                let suffix = "." + locale + ext
                if relative.hasSuffix(suffix) {
                    return locale + "/" + String(relative.dropLast(suffix.count)) + ".html"
                }
            }
        }
        if relative.hasSuffix(".md") {
            return String(relative.dropLast(3)) + ".html"
        }
        return relative
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

        var links: [String] = []
        var defaultURL: String?
        for alternate in localization.locales {
            let (sourceFiles, url): ([String], String)
            if alternate == defaultLocale {
                sourceFiles = [base + ".md", base + ".html"]
                url = "/" + base + ".html"
            } else {
                sourceFiles = [base + "." + alternate + ".md", base + "." + alternate + ".html"]
                url = "/" + alternate + "/" + base + ".html"
            }
            guard sourceFiles.contains(where: {
                site.fileSystem.fileExists(
                    atPath: site.sourceDirectory.appendingPathComponent($0).path
                )
            }) else { continue }
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
        var results: [URL] = []
        func walk(_ current: URL) throws {
            for entry in try fileSystem.contentsOfDirectory(at: current) {
                if fileSystem.isDirectory(atPath: entry.path) {
                    try walk(entry)
                } else if matches(glob: glob, path: relativePath(of: entry, to: directory)) {
                    results.append(entry)
                }
            }
        }
        try walk(directory)
        return results.sorted { $0.path < $1.path }
    }

    private func relativePath(of url: URL, to base: URL) -> String {
        let basePath = base.path
        let path = url.path
        guard path.hasPrefix(basePath) else { return path }
        return String(path.dropFirst(basePath.count + 1))
    }

    /// Matches a relative path against a glob. Supports `*` (any characters
    /// except `/`), `**/` (any number of directories, including none), and
    /// `{a,b}` (alternation).
    private func matches(glob: String, path: String) -> Bool {
        guard let pattern = Self.globPattern(from: glob) else { return false }
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$") else { return false }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    /// Converts a glob into a regular-expression pattern, or `nil` if the
    /// glob is malformed (an unterminated `{`).
    private static func globPattern(from glob: String) -> String? {
        var pattern = ""
        var index = glob.startIndex
        while index < glob.endIndex {
            let character = glob[index]
            if character == "*" {
                if glob[index...].hasPrefix("**/") {
                    pattern += "(?:[^/]+/)*"
                    index = glob.index(index, offsetBy: 3)
                    continue
                } else if glob[index...].hasPrefix("**") {
                    pattern += ".*"
                    index = glob.index(index, offsetBy: 2)
                    continue
                } else {
                    pattern += "[^/]*"
                }
            } else if character == "{" {
                guard let close = glob[index...].firstIndex(of: "}") else { return nil }
                let alternatives = glob[glob.index(after: index)..<close]
                    .split(separator: ",")
                    .compactMap { globPattern(from: String($0)) }
                guard !alternatives.isEmpty else { return nil }
                pattern += "(?:" + alternatives.joined(separator: "|") + ")"
                index = glob.index(after: close)
                continue
            } else if ".\\+?()[]{}^$|".contains(character) {
                pattern += "\\" + String(character)
            } else {
                pattern += String(character)
            }
            index = glob.index(after: index)
        }
        return pattern
    }
}
