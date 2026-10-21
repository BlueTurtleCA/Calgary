import Foundation

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
public final class Site {
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

    /// The site's localization configuration, if any.
    private(set) var localization: Localization?

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
    public init(
        name: String,
        source: String = "content",
        output: String = "build",
        root: URL? = nil,
        fileSystem: any FileSystem = LocalFileSystem(),
        commandRunner: any CommandRunner = ProcessCommandRunner(),
        templateVariables: [String: Variable] = [:]
    ) {
        self.name = name
        self.source = source
        self.output = output
        self.root = root ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
        self.templateVariables = templateVariables
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
    ///     `PATH` (for example, `"npx"`) or a path to an executable.
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
        addStep(ExecuteCommandStep(command: command, arguments: arguments, input: input, output: output))
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
    /// build. On platforms without Network.framework the step fails the
    /// build.
    ///
    /// - Parameter port: The port to listen on. Defaults to `8080`.
    @discardableResult
    public func serve(port: Int = 8080) -> Site {
        addStep(ServeSiteStep(port: port))
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

    private func prepareOutputDirectory() throws {
        if fileSystem.fileExists(atPath: outputDirectory.path) {
            try fileSystem.removeItem(at: outputDirectory)
        }
        try fileSystem.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }
}
