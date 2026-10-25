import Foundation

/// A build step that writes a `sitemap.xml` of the site's pages to the
/// output directory.
///
/// The sitemap lists every `.html` file in the output directory under
/// `baseUrl`, so the step runs after the steps that produce pages:
///
/// ```swift
/// site.renderPages()
///     .generateSitemap(baseUrl: "https://example.com")
/// ```
///
/// `index.html` files are listed as their directory's URL: the root
/// `index.html` becomes `https://example.com/`, and `fr-fr/index.html`
/// becomes `https://example.com/fr-fr/`.
struct SitemapStep: BuildStep {
    /// The site's public base URL, for example `"https://example.com"`.
    let baseUrl: String

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    var name: String {
        "Generate sitemap for '\(baseUrl)'"
    }

    func run(site: Site) throws {
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
        for page in pages {
            let relative = fileSystem.relativePath(of: page, to: outputDirectory)
            entries.append("<url><loc>\(Self.loc(for: relative, baseUrl: baseUrl))</loc></url>")
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        \(entries.joined(separator: "\n"))
        </urlset>
        """
        try fileSystem.write(Data(xml.utf8), to: outputDirectory.appendingPathComponent("sitemap.xml"))
    }

    /// The absolute URL for a page's output path: `index.html` files are
    /// listed as their directory's URL.
    static func loc(for relative: String, baseUrl: String) -> String {
        var path = relative
        if path.hasSuffix("index.html") {
            path = String(path.dropLast("index.html".count))
        }
        let base = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        return base + "/" + path.xmlEscaped
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
