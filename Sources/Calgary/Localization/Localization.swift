/// The site's localization configuration, set with `Site.localize`.
struct Localization: Sendable {
    /// The site's default (fallback) locale, for example `"en"`.
    let defaultLocale: String

    /// Every locale the site is published in, including the default.
    let locales: [String]

    /// The source of the site's strings, relative to the site's root, if any:
    /// a directory of per-locale YAML files, or an Xcode string catalog
    /// (`.xcstrings`) file.
    let stringsPath: String?
}
