//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// Site.swift
//

import Foundation

/// A collection of pages that share a template and get a generated index,
/// optionally paginated: a blog, a gallery, a docs section.
///
/// A collection is declared with `Site.addCollection(name:source:template:
/// index:paginate:)` and rendered by `renderPages()`: its pages render like
/// any other page (using the collection's template when their frontmatter
/// declares none), and after the pages render, the collection's index
/// template renders once per page of the collection.
struct SiteCollection: Sendable {
    /// The name the collection is exposed to templates under:
    /// `{{ site.<name> }}`.
    let name: String
    /// The directory of the collection's pages, relative to the source
    /// directory (for example, `"blog"` for `content/blog`).
    let source: String
    /// The template the collection's pages render with when their frontmatter
    /// declares none.
    let template: String
    /// The template the collection's index (and pagination) pages render
    /// with.
    let index: String
    /// The number of pages per index page; `nil` renders a single index page
    /// with every page.
    let paginate: Int?
}

/// A static site and its build pipeline.
///
/// A `Site` is configured with a builder-style API: each method appends a
/// `BuildStep` to the pipeline and returns the site, so steps can be
/// daisy-chained:
///
/// ```swift
/// let site = Site(name: "Blue Turtle Canada", source: "content", output: "build")
///     .copyAssets(from: "assets")
///
/// try site.build()
/// ```
///
/// Relative paths given to the initializer are resolved against `root`,
/// which defaults to the current working directory.
///
/// `Site` is not thread-safe. It is marked `@unchecked Sendable` so the
/// serve step's hot-reload closure can capture it: a build runs
/// synchronously on one thread, and while the serve step blocks that
/// thread, its rebuilds run one at a time on the watcher's queue, so at
/// most one thread touches a site at a time.
public final class Site: @unchecked Sendable {
    /// The site's name.
    public let name: String

    /// The source directory, relative to `root` (for example, `"content"`).
    public let source: String

    /// The output directory, relative to `root` (for example, `"build"`).
    public let output: String

    /// The directory that relative paths are resolved against.
    ///
    /// Defaults to the current working directory, which is the consumer's
    /// project root when they run their executable from the terminal.
    /// When the executable is run from Xcode's run button, the working
    /// directory is DerivedData instead — pass an explicit `root` in that
    /// case, for example one anchored to the pipeline file's location with
    /// `URL(fileURLWithPath: #filePath)`.
    public let root: URL

    /// The file system the build steps use.
    ///
    /// Defaults to `LocalFileSystem`, which wraps `FileManager`.
    public let fileSystem: any FileSystem

    /// The runner the build steps use to execute external commands.
    ///
    /// Defaults to `ProcessCommandRunner`, which runs real processes.
    public let commandRunner: any CommandRunner

    /// The directory of registered templates, relative to `root`, if any.
    public private(set) var templatesDirectory: String?

    /// The directory of registered components, relative to `root`, if any.
    public private(set) var componentsDirectory: String?

    /// Site-wide template variables, exposed to templates and components
    /// under the `site` namespace: `templateVariables: ["year": .string("2026")]`
    /// renders as `{{ site.year }}` on every page.
    ///
    /// Values layer on top of the built-in `site` variables, so an entry
    /// named `name` overrides `site.name`.
    public let templateVariables: [String: Variable]

    /// The site's public base URL, for example `"https://example.com"`.
    ///
    /// When set, pages get a `page.canonical` built-in variable (the page's
    /// absolute URL, ready to paste into a `<link rel="canonical">` tag), and
    /// `generateSitemap()` can be called without a base URL.
    public let baseUrl: String?

    /// The site's localization configuration, if any.
    private(set) var localization: Localization?

    /// The site's collections, in the order they were added.
    private(set) var collections: [SiteCollection] = []

    /// The steps in the pipeline, in the order they will run.
    public private(set) var steps: [any BuildStep] = []

    /// Warnings collected during the build, printed when the build finishes.
    public private(set) var warnings: [String] = []

    /// Creates a site.
    ///
    /// - Parameters:
    ///   - name: The site's name.
    ///   - source: The source directory, relative to `root`.
    ///   - output: The output directory, relative to `root`.
    ///   - root: The directory that relative paths are resolved against.
    ///     Defaults to the current working directory, which is not the
    ///     project root when the executable is run from Xcode's run
    ///     button — pass an explicit `root` in that case.
    ///   - fileSystem: The file system the build steps use.
    ///     Defaults to `LocalFileSystem`.
    ///   - commandRunner: The runner used to execute external commands.
    ///     Defaults to `ProcessCommandRunner`.
    ///   - templateVariables: Site-wide variables exposed to templates and
    ///     components under the `site` namespace, for example
    ///     `["year": .string("2026")]` renders as `{{ site.year }}`.
    ///     Defaults to an empty dictionary.
    ///   - baseUrl: The site's public base URL, for example
    ///     `"https://example.com"`. When set, pages get a `page.canonical`
    ///     built-in variable and `generateSitemap()` can be called without a
    ///     base URL. Defaults to `nil`.
    public init(
        name: String,
        source: String = "content",
        output: String = "build",
        root: URL? = nil,
        fileSystem: any FileSystem = LocalFileSystem(),
        commandRunner: any CommandRunner = ProcessCommandRunner(),
        templateVariables: [String: Variable] = [:],
        baseUrl: String? = nil
    ) {
        self.name = name
        self.source = source
        self.output = output
        self.root = root ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
        self.templateVariables = templateVariables
        self.baseUrl = baseUrl
    }

    /// The resolved source directory (for example, `/path/to/project/content`).
    public var sourceDirectory: URL {
        root.appendingPathComponent(source)
    }

    /// The resolved output directory (for example, `/path/to/project/build`).
    public var outputDirectory: URL {
        root.appendingPathComponent(output)
    }

    /// Adds a custom step to the pipeline.
    ///
    /// - Parameter step: The step to run during the build.
    /// - Returns: The site, so calls can be daisy-chained.
    @discardableResult
    public func addStep(_ step: some BuildStep) -> Site {
        steps.append(step)
        return self
    }

    /// Adds a step that copies the contents of `from` into the output
    /// directory, preserving relative paths:
    ///
    /// ```
    /// assets/css/site.css    →  build/css/site.css
    /// assets/images/logo.png →  build/images/logo.png
    /// ```
    ///
    /// - Parameter from: The assets directory to copy from, relative to `root`.
    /// - Returns: The site, so calls can be daisy-chained.
    @discardableResult
    public func copyAssets(from: String) -> Site {
        addStep(CopyAssetsStep(from: from))
    }

    /// Adds a step that runs an external command.
    ///
    /// The command runs with the site's root as its working directory, so
    /// relative paths in its arguments resolve against the project. Its
    /// `input` and `output` declare the files it reads and writes; both are
    /// validated so a broken command fails the build with a clear error:
    ///
    /// ```swift
    /// site.executeCommand(
    ///     "npx",
    ///     arguments: ["tailwindcss", "-i", "assets/css/input.css", "-o", "build/css/site.css"],
    ///     input: "assets/css/input.css",
    ///     output: "build/css/site.css"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - command: The executable to run. Either a name resolved against
    ///     `PATH` and the runner's additional search directories (for
    ///     example, `"npx"`) or a path to an executable.
    ///   - arguments: Arguments passed to the command.
    ///   - input: The file the command reads, relative to `root`.
    ///     The build fails if it does not exist.
    ///   - output: The file the command writes, relative to `root`.
    ///     The build fails if it does not exist after the command finishes.
    /// - Returns: The site, so calls can be daisy-chained.
    @discardableResult
    public func executeCommand(
        _ command: String,
        arguments: [String] = [],
        input: String? = nil,
        output: String? = nil
    ) -> Site {
        addStep(
            ExecuteCommandStep(
                fallback: CommandInvocation(command, arguments: arguments),
                input: input,
                output: output
            )
        )
    }

    /// Adds a step that runs an external command, with per-platform
    /// overrides when a command differs by platform.
    ///
    /// The command runs with the site's root as its working directory. The
    /// given invocation runs on every platform that has no override; an
    /// override replaces both the command and its arguments on its platform,
    /// so a pipeline can declare one command that builds on macOS, Linux,
    /// and Windows without platform conditionals:
    ///
    /// ```swift
    /// site.executeCommand(
    ///     CommandInvocation("npx", arguments: ["--yes", "@tailwindcss/cli", "-i", "input.css", "-o", "output.css"]),
    ///     windows: CommandInvocation("npx.cmd", arguments: ["--yes", "@tailwindcss/cli", "-i", "input.css", "-o", "output.css"]),
    ///     input: "input.css",
    ///     output: "output.css"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - invocation: The command to run when the platform has no override.
    ///   - windows: The command to run on Windows, if it differs.
    ///   - macos: The command to run on macOS, if it differs.
    ///   - linux: The command to run on Linux, if it differs.
    ///   - input: The file the command reads, relative to `root`.
    ///     The build fails if it does not exist.
    ///   - output: The file the command writes, relative to `root`.
    ///     The build fails if it does not exist after the command finishes.
    /// - Returns: The site, so calls can be daisy-chained.
    @discardableResult
    public func executeCommand(
        _ invocation: CommandInvocation,
        windows: CommandInvocation? = nil,
        macos: CommandInvocation? = nil,
        linux: CommandInvocation? = nil,
        input: String? = nil,
        output: String? = nil
    ) -> Site {
        addStep(
            ExecuteCommandStep(
                fallback: invocation,
                windows: windows,
                macos: macos,
                linux: linux,
                input: input,
                output: output
            )
        )
    }

    /// Registers the directory that contains the site's templates.
    ///
    /// Templates are HTML files with `{{ variable }}` interpolation and
    /// `{% include %}` tags. A page's frontmatter selects its template by
    /// name: `template: home` renders with `<directory>/home.html`.
    @discardableResult
    public func registerTemplates(in directory: String) -> Site {
        templatesDirectory = directory
        return self
    }

    /// Registers the directory that contains the site's components.
    ///
    /// Components are markdown (`.md`) or HTML (`.html`) partials that
    /// templates and pages can include with
    /// `{% include "components/hero" %}`.
    @discardableResult
    public func registerComponents(in directory: String) -> Site {
        componentsDirectory = directory
        return self
    }

    /// Configures localization for the site.
    ///
    /// Pages for the default locale are written to the output root, and pages
    /// for other locales are written under a subfolder named after the locale,
    /// with the locale suffix removed from the file name:
    ///
    /// ```
    /// content/index.md        →  build/index.html
    /// content/index.fr-fr.md  →  build/fr-fr/index.html
    /// ```
    ///
    /// A page file is a translation when its name ends in `.<locale>.md` or
    /// `.<locale>.html` for a declared non-default locale. When `strings` is
    /// set, the active locale's strings (falling back to the default locale)
    /// are exposed to templates and components as `{{ strings.… }}`.
    ///
    /// - Parameters:
    ///   - defaultLocale: The site's default (fallback) locale, for example `"en"`.
    ///   - locales: The other locales the site is published in, for example `["fr-fr"]`.
    ///   - strings: The source of the site's strings, relative to `root`: a
    ///     directory of per-locale YAML files, or an Xcode string catalog
    ///     (`.xcstrings`) file. `nil` disables string lookup.
    @discardableResult
    public func localize(
        defaultLocale: String,
        locales: [String] = [],
        strings: String? = nil
    ) -> Site {
        localization = Localization(
            defaultLocale: defaultLocale,
            locales: [defaultLocale] + locales,
            stringsPath: strings
        )
        return self
    }

    /// Adds a collection of pages that share a template and get a generated
    /// index, optionally paginated.
    ///
    /// A collection is a directory of pages under the site's source directory
    /// — for example, a blog's posts in `content/blog`. Each page renders
    /// like any other page, using `template` when its frontmatter declares no
    /// `template` of its own. After the pages render, the collection's index
    /// template renders once per page of the collection:
    ///
    /// - with `paginate: nil`, a single `<output>/<source>/index.html`
    ///   listing every page;
    /// - with `paginate: n`, `<output>/<source>/index.html` plus
    ///   `<output>/<source>/page/2/index.html`, and so on, each listing `n`
    ///   pages.
    ///
    /// The collection's pages are exposed to every template as
    /// `{{ site.<name> }}`: a list sorted by `date` descending (pages without
    /// a `date` last), each entry carrying the page's `title`, `url`,
    /// `locale`, `date`, and every frontmatter variable, so an index template
    /// can show a post's `description` or `image`.
    ///
    /// The index template renders with the pagination variables `items` (the
    /// pages on this page), `total`, `count`, `number`, `pageCount`,
    /// `hasPrevious`, `hasNext`, and (when present) `previousUrl` and
    /// `nextUrl`, plus the usual `site` and `page` built-ins.
    ///
    /// A site can have several collections (a blog and a gallery, for
    /// example); each is exposed under its own name and renders its index
    /// under its own directory.
    ///
    /// - Parameters:
    ///   - name: The name the collection is exposed under, for example
    ///     `"blog"` renders as `{{ site.blog }}`. Must be unique and must not
    ///     collide with a built-in `site` variable.
    ///   - source: The directory of the collection's pages, relative to the
    ///     source directory (for example, `"blog"` for `content/blog`).
    ///   - template: The template the collection's pages render with when
    ///     their frontmatter declares none.
    ///   - index: The template the collection's index pages render with.
    ///   - paginate: The number of pages per index page. `nil` renders a
    ///     single index page with every page. Defaults to `nil`.
    @discardableResult
    public func addCollection(
        name: String,
        source: String,
        template: String,
        index: String,
        paginate: Int? = nil
    ) -> Site {
        collections.append(
            SiteCollection(
                name: name,
                source: source,
                template: template,
                index: index,
                paginate: paginate
            )
        )
        return self
    }

    /// Adds a step that renders pages into HTML.
    ///
    /// Pages are found by `glob` under the site's source directory. Markdown
    /// pages (`.md`) have YAML frontmatter and are rendered into their
    /// registered template; HTML pages (`.html`) are standalone documents
    /// rendered by the template engine without markdown conversion. Each page
    /// is written to the output directory, mirroring its source path:
    /// `content/blog/post.md` becomes `build/blog/post.html`.
    ///
    /// When the site is localized, a default-locale HTML page is locale-neutral
    /// content: it is also rendered for every other declared locale, so its
    /// strings and variables pick up that locale, unless an explicit
    /// `<name>.<locale>.html` or `<name>.<locale>.md` translation exists, in
    /// which case that file takes precedence. A default-locale markdown page
    /// without a translation renders only for the default locale and the build
    /// reports a warning.
    @discardableResult
    public func renderPages(glob: String = "**/*.{md,html}") -> Site {
        addStep(RenderPagesStep(glob: glob))
    }

    /// Adds a step that minifies the site's output.
    ///
    /// Files matching `glob` (relative to the output directory) are
    /// rewritten in place: HTML files have their comments removed and their
    /// whitespace collapsed, and CSS files have their comments removed and
    /// their whitespace collapsed. The contents of raw HTML elements
    /// (`<script>`, `<style>`, `<textarea>`, `<pre>`, and `<code>`) and of
    /// CSS strings are left untouched.
    ///
    /// Because the step rewrites files in the output directory, it runs
    /// after the steps that produce them:
    ///
    /// ```swift
    /// site.copyAssets(from: "assets")
    ///     .renderPages()
    ///     .minify()
    /// ```
    ///
    /// JavaScript is not minified: a matched file that is not `.html` or
    /// `.css` is skipped with a warning. Run a real minifier with
    /// `executeCommand` if a site needs JS minification.
    ///
    /// - Parameter glob: The output files to minify. Defaults to
    ///   `"**/*.{html,css}"`.
    @discardableResult
    public func minify(glob: String = "**/*.{html,css}") -> Site {
        addStep(MinifyStep(glob: glob))
    }

    /// Adds a step that writes a `sitemap.xml` of the site's pages to the
    /// output directory.
    ///
    /// The sitemap lists every `.html` file in the output directory under
    /// the base URL, so the step runs after the steps that produce pages:
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
    /// declared, otherwise the page's source file modification time — and,
    /// when the site is localized, `<xhtml:link rel="alternate"
    /// hreflang="…">` entries for every locale the page is published in,
    /// mirroring the page's `page.alternates`.
    ///
    /// - Parameter baseUrl: The site's public base URL, for example
    ///   `"https://example.com"`. Defaults to the site's `baseUrl` when the
    ///   site was created with one; the build fails if neither is set.
    @discardableResult
    public func generateSitemap(baseUrl: String? = nil) -> Site {
        addStep(SitemapStep(baseUrl: baseUrl))
    }

    /// Adds a step that checks the internal links in the site's output.
    ///
    /// Every `href` in the output files matching `glob` is resolved the way
    /// the site's server resolves requests, and the build reports a warning
    /// for each link that does not resolve to a built file:
    ///
    /// ```swift
    /// site.renderPages()
    ///     .checkLinks()
    /// ```
    ///
    /// Links with a scheme (`https://`, `mailto:`, …), fragment-only links
    /// (`#section`), and anchors on the current page are skipped. A link to
    /// a directory resolves to that directory's `index.html`, so `/blog/`
    /// checks out when `blog/index.html` is built.
    ///
    /// - Parameter glob: The output files to check, relative to the output
    ///   directory. Defaults to `"**/*.html"`.
    @discardableResult
    public func checkLinks(glob: String = "**/*.html") -> Site {
        addStep(CheckLinksStep(glob: glob))
    }

    /// Adds a step that opens a built page in the default browser.
    ///
    /// - Parameter page: The page to open, relative to the output directory.
    ///   Defaults to `"index.html"`.
    @discardableResult
    public func open(_ page: String = "index.html") -> Site {
        addStep(OpenSiteStep(page: page))
    }

    /// Adds a step that serves the built site over HTTP and opens it in the
    /// default browser.
    ///
    /// The server listens on `http://localhost:<port>/` and serves the
    /// output directory, so absolute paths in the site (for example,
    /// `/css/site.css`) resolve the same way they do in production. Unlike
    /// `open(_:)`, which opens a single file and finishes, the step keeps
    /// the process running: it blocks until the process is interrupted
    /// (for example, with Ctrl-C), which stops the server and ends the
    /// build.
    ///
    /// When `hotReload` is enabled (the default), the site's root is
    /// watched for file changes: a change re-runs the pipeline's
    /// non-terminal steps in place and tells every open browser to reload,
    /// so edits to pages, templates, components, and assets (including the
    /// CSS source) appear without a manual refresh. The watcher uses
    /// FSEvents on Apple platforms and a polling watcher elsewhere.
    ///
    /// - Parameters:
    ///   - port: The port to listen on. Defaults to `8080`.
    ///   - hotReload: Whether file changes trigger a rebuild and a browser
    ///     reload. Defaults to `true`.
    @discardableResult
    public func serve(port: Int = 8080, hotReload: Bool = true) -> Site {
        addStep(ServeSiteStep(port: port, hotReload: hotReload))
    }

    /// Records a warning to be reported when the build finishes.
    ///
    /// Steps use this for non-fatal problems — for example, a missing
    /// translation of a page — that should be surfaced without failing the
    /// build.
    public func warn(_ message: String) {
        warnings.append(message)
    }

    /// Runs the build.
    ///
    /// The output directory is removed and recreated, then each step runs in
    /// the order it was added. Warnings collected during the build are
    /// printed when it finishes.
    ///
    /// - Throws: A `BuildError` if the output directory cannot be prepared or
    ///   a step fails.
    public func build() throws {
        warnings.removeAll()
        try prepareOutputDirectory()
        for step in steps {
            print("  \(step.name)")
            do {
                try step.run(site: self)
            } catch let error as BuildError {
                throw error
            } catch {
                throw BuildError.stepFailed(step: step.name, underlying: error)
            }
        }
        for warning in warnings {
            print("warning: \(warning)")
        }
    }

    /// Re-runs the pipeline's non-terminal steps in place.
    ///
    /// Unlike `build()`, the output directory is not removed first, so a
    /// server serving it can keep answering requests while the site is
    /// rebuilt. Terminal steps (serving, opening a browser) are skipped.
    /// Warnings collected during the rebuild are printed when it finishes.
    ///
    /// - Throws: A `BuildError` if a step fails.
    func rebuild() throws {
        warnings.removeAll()
        for step in steps where !step.isTerminal {
            print("  \(step.name)")
            do {
                try step.run(site: self)
            } catch let error as BuildError {
                throw error
            } catch {
                throw BuildError.stepFailed(step: step.name, underlying: error)
            }
        }
        for warning in warnings {
            print("warning: \(warning)")
        }
    }

    private func prepareOutputDirectory() throws {
        if fileSystem.fileExists(atPath: outputDirectory.path) {
            try fileSystem.removeItem(at: outputDirectory)
        }
        try fileSystem.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }
}
