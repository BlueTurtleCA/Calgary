import Foundation

/// A build step that writes a `sitemap.xml` of the site's pages to the
/// output directory.
///
/// The sitemap lists every `.html` file in the output directory under the
/// base URL, so the step runs after the steps that produce pages:
///
/// ```swift
/// site.renderPages()
///     .generateSitemap(baseUrl: "https://example.com")
/// ```
///
/// `index.html` files are listed as their directory's URL: the root
/// `index.html` becomes `https://example.com/`, and `fr-fr/index.html`
/// becomes `https://example.com/fr-fr/`.
///
/// Each entry carries a `<lastmod>` — the page's frontmatter `date` when
/// declared, otherwise the page's source file modification time, falling
/// back to the built file's modification time — and, when the site is
/// localized, `<xhtml:link rel="alternate" hreflang="…">` entries for every
/// locale the page is published in, mirroring the page's `page.alternates`.
struct SitemapStep: BuildStep {
    /// The base URL for the sitemap, if not taken from the site.
    let baseUrl: String?

    init(baseUrl: String? = nil) {
        self.baseUrl = baseUrl
    }

    var name: String {
        if let baseUrl {
            return "Generate sitemap for '\(baseUrl)'"
        }
        return "Generate sitemap"
    }

    func run(site: Site) throws {
        guard let baseUrl = baseUrl ?? site.baseUrl else {
            throw BuildError.missingConfiguration(
                "generateSitemap requires a base URL (pass baseUrl: or create the Site with one)"
            )
        }

        let fileSystem = site.fileSystem
        let outputDirectory = site.outputDirectory

        guard fileSystem.fileExists(atPath: outputDirectory.path) else {
            throw BuildError.missingPath(outputDirectory.path)
        }

        let pages = try fileSystem.files(in: outputDirectory)
            .filter { $0.path.hasSuffix(".html") }

        guard !pages.isEmpty else {
            site.warn("no pages found in the output directory; 'sitemap.xml' was not written")
            return
        }

        var entries: [String] = []
        var hasAlternates = false
        for page in pages {
            let relative = fileSystem.relativePath(of: page, to: outputDirectory)
            let entry = Entry(
                loc: Self.loc(for: relative, baseUrl: baseUrl),
                lastmod: lastmod(for: relative, page: page, site: site),
                alternates: alternates(for: relative, site: site, baseUrl: baseUrl)
            )
            if !entry.alternates.isEmpty {
                hasAlternates = true
            }
            entries.append(render(entry))
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\(hasAlternates ? " xmlns:xhtml=\"http://www.w3.org/1999/xhtml\"" : "")>
        \(entries.joined(separator: "\n"))
        </urlset>
        """
        try fileSystem.write(Data(xml.utf8), to: outputDirectory.appendingPathComponent("sitemap.xml"))
    }

    // MARK: Entries

    /// A single `<url>` entry in the sitemap.
    private struct Entry {
        let loc: String
        let lastmod: String?
        let alternates: [(locale: String, url: String)]
    }

    /// Renders an entry as one line of XML.
    private func render(_ entry: Entry) -> String {
        var xml = "<url><loc>\(entry.loc)</loc>"
        if let lastmod = entry.lastmod {
            xml += "<lastmod>\(lastmod)</lastmod>"
        }
        for alternate in entry.alternates {
            xml += "<xhtml:link rel=\"alternate\" hreflang=\"\(alternate.locale.xmlEscaped)\" href=\"\(alternate.url)\"/>"
        }
        return xml + "</url>"
    }

    /// The absolute URL for a page's output path: `index.html` files are
    /// listed as their directory's URL.
    static func loc(for relative: String, baseUrl: String) -> String {
        PageURL.absolute(for: relative, baseUrl: baseUrl).xmlEscaped
    }

    // MARK: Lastmod

    /// The page's `<lastmod>` value: its frontmatter `date` when declared,
    /// falling back to the page's source file modification time, then to the
    /// built file's modification time. `nil` when no date can be determined.
    private func lastmod(for relative: String, page: URL, site: Site) -> String? {
        let fileSystem = site.fileSystem
        if let source = sourceFile(for: relative, site: site) {
            if let date = frontmatterDate(of: source, fileSystem: fileSystem) {
                return Self.format(date)
            }
            if let modified = fileSystem.modificationDate(of: source) {
                return Self.format(modified)
            }
        }
        if let modified = fileSystem.modificationDate(of: page) {
            return Self.format(modified)
        }
        return nil
    }

    /// The source file for a page's output path, if any.
    ///
    /// `blog/post.html` maps to `content/blog/post.md` or
    /// `content/blog/post.html`. A page under a locale subfolder maps to its
    /// locale-suffixed source file first, then to the default-locale source,
    /// which a default-locale HTML page renders for every declared locale.
    private func sourceFile(for relative: String, site: Site) -> URL? {
        let fileSystem = site.fileSystem
        let sourceDirectory = site.sourceDirectory
        guard fileSystem.fileExists(atPath: sourceDirectory.path) else {
            return nil
        }

        var path = relative
        var localeSuffix = ""
        if let localization = site.localization,
           let first = path.split(separator: "/").first.map(String.init),
           first != localization.defaultLocale,
           localization.locales.contains(first)
        {
            path = String(path.dropFirst(first.count + 1))
            localeSuffix = "." + first
        }
        let base = path.hasSuffix(".html") ? String(path.dropLast(".html".count)) : path

        var candidates = [base + localeSuffix + ".md", base + localeSuffix + ".html"]
        if !localeSuffix.isEmpty {
            candidates += [base + ".md", base + ".html"]
        }
        for candidate in candidates {
            let url = sourceDirectory.appendingPathComponent(candidate)
            if fileSystem.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// The date a page's frontmatter declares, if any and if it parses.
    private func frontmatterDate(of url: URL, fileSystem: any FileSystem) -> Date? {
        guard let data = try? fileSystem.read(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let isHTMLPage = url.path.hasSuffix(".html")
        let page = isHTMLPage ? try? Frontmatter.parseHTML(text) : try? Frontmatter.parse(text)
        guard let page, let dateString = page.date else {
            return nil
        }
        return Self.parse(dateString)
    }

    /// Parses a frontmatter date, trying the common formats.
    private static func parse(_ string: String) -> Date? {
        let formats = ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    /// Formats a date for the sitemap's `<lastmod>` element: ISO 8601 in
    /// UTC, for example `2026-01-01T00:00:00Z`.
    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: Alternates

    /// The page's hreflang alternates, from the built output: one per
    /// declared locale whose version of the page exists in the output, plus
    /// an `x-default` entry for the default locale. Empty when the site is
    /// not localized.
    private func alternates(for relative: String, site: Site, baseUrl: String) -> [(locale: String, url: String)] {
        guard let localization = site.localization else {
            return []
        }
        let fileSystem = site.fileSystem
        let outputDirectory = site.outputDirectory

        var path = relative
        if let first = path.split(separator: "/").first.map(String.init),
           first != localization.defaultLocale,
           localization.locales.contains(first)
        {
            path = String(path.dropFirst(first.count + 1))
        }
        let base = path.hasSuffix(".html") ? String(path.dropLast(".html".count)) : path

        var alternates: [(locale: String, url: String)] = []
        var defaultURL: String?
        for locale in localization.locales {
            let relativeURL = PageURL.relative(forBase: base, in: locale, defaultLocale: localization.defaultLocale)
            let outputPath = String(relativeURL.dropFirst())
            guard fileSystem.fileExists(atPath: outputDirectory.appendingPathComponent(outputPath).path) else {
                continue
            }
            let url = Self.loc(for: outputPath, baseUrl: baseUrl)
            alternates.append((locale: locale, url: url))
            if locale == localization.defaultLocale {
                defaultURL = url
            }
        }
        if let defaultURL {
            alternates.append((locale: "x-default", url: defaultURL))
        }
        return alternates
    }
}

private extension String {
    /// The string with the characters that are significant in XML escaped.
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
