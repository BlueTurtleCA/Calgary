/// Shared helpers for a page's URLs in the built site.
///
/// A page's **URL path** is its location relative to the site root, with no
/// leading or trailing slash and no file extension: the root page is `""`,
/// and a post is `blog/hello-world`. Every other form of a page's location is
/// derived from its URL path:
///
/// - the **output file path** is `index.html` for the root and
///   `<url path>/index.html` otherwise;
/// - the **URL** is `/` for the root and `/<url path>` otherwise.
///
/// `RenderPagesStep` uses these helpers for the `page.url` and `page.canonical`
/// built-in variables, and `SitemapStep` uses them for the sitemap's `<loc>`
/// and `<xhtml:link>` entries, so the two always agree on a page's URLs.
enum PageURL {
    /// The URL path for a page's output path: `index.html` files are the
    /// directory's URL, so `index.html` is `""` and
    /// `blog/hello-world/index.html` is `blog/hello-world`.
    static func path(for outputRelative: String) -> String {
        var path = outputRelative
        if path.hasSuffix("index.html") {
            path = String(path.dropLast("index.html".count))
        }
        if path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        return path
    }

    /// The output file path for a URL path: `index.html` for the root
    /// (`""`), otherwise `<path>/index.html`.
    static func outputPath(forURLPath urlPath: String) -> String {
        urlPath.isEmpty ? "index.html" : urlPath + "/index.html"
    }

    /// The URL for a URL path: `/` for the root (`""`), otherwise `/<path>`.
    static func url(forURLPath urlPath: String) -> String {
        urlPath.isEmpty ? "/" : "/" + urlPath
    }

    /// The absolute URL for a page's output path under `baseUrl`, for example
    /// `https://example.com/blog/hello-world` for
    /// `blog/hello-world/index.html`.
    static func absolute(for outputRelative: String, baseUrl: String) -> String {
        absolute(forURLPath: path(for: outputRelative), baseUrl: baseUrl)
    }

    /// The absolute URL for a URL path under `baseUrl`, for example
    /// `https://example.com/blog/hello-world` for `blog/hello-world`.
    static func absolute(forURLPath urlPath: String, baseUrl: String) -> String {
        let base = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        return urlPath.isEmpty ? base + "/" : base + "/" + urlPath
    }
}
