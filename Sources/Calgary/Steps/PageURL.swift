/// Shared helpers for a page's URLs in the built site.
///
/// `RenderPagesStep` uses them for the `page.canonical` and `page.alternates`
/// built-in variables, and `SitemapStep` uses them for the sitemap's `<loc>`
/// and `<xhtml:link>` entries, so the two always agree on a page's URLs.
enum PageURL {
    /// The URL path for a page's output path: `index.html` files are listed
    /// as their directory's URL, so `index.html` is `""` and
    /// `fr-fr/index.html` is `fr-fr/`.
    static func path(for outputRelative: String) -> String {
        if outputRelative.hasSuffix("index.html") {
            return String(outputRelative.dropLast("index.html".count))
        }
        return outputRelative
    }

    /// The absolute URL for a page's output path under `baseUrl`, for example
    /// `https://example.com/fr-fr/` for `fr-fr/index.html`.
    static func absolute(for outputRelative: String, baseUrl: String) -> String {
        let base = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        return base + "/" + path(for: outputRelative)
    }

    /// The URL of a page's base in a locale, relative to the site root:
    /// `index` in the default locale is `/index.html`, in `fr-fr` it is
    /// `/fr-fr/index.html`.
    static func relative(forBase base: String, in locale: String, defaultLocale: String) -> String {
        locale == defaultLocale ? "/" + base + ".html" : "/" + locale + "/" + base + ".html"
    }
}
