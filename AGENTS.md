# AGENTS.md — Calgary

Guidance for AI agents (and humans) working in this repository.

## What this project is

**Calgary** is a custom static site generator, distributed as a Swift package with a **library product**: downstream projects add Calgary as a dependency, `import Calgary`, and write their own pipeline — a `Main.swift` file in an executable target that declares the build steps (copy assets, build CSS, register templates, render pages, open the result). Content and templates are plain files (markdown + HTML); the **build pipeline itself is Swift code**.

This repo contains two things:
- **The library** (`Sources/Calgary/`) — the importable SSG.
- **A sample site** (`Sources/Example/`) — the "Blue Turtle Canada" demo that uses the library. Its content (`content/`, `templates/`, `components/`, `assets/`) lives next to its pipeline file (`Main.swift`). It is the reference example of how downstream projects use Calgary, and doubles as an integration test. Running the `Calgary-Package` scheme's run action (or `swift run Example` from the package root) produces `Sources/Example/build/` and opens the site in a browser.

Design intent (deliberate distinctions):
- **Not Ignite** — HTML is not generated from Swift code; Swift only orchestrates the build.
- **Not Hugo/Jekyll** — the pipeline is not driven by config files; it is Swift code in the repo.
- **Files** = what a writer edits (pages, components, templates, assets).
- **Swift** = how the site is assembled (the pipeline).

## Package layout

```
Calgary/
├── Package.swift                             # declares the "Calgary" library product
├── Sources/
│   ├── Calgary/                              # the importable SSG library (the product)
│   │   ├── Site.swift                        # builder API + build orchestration
│   │   ├── Steps/
│   │   │   ├── BuildStep.swift               # step protocol + BuildError
│   │   │   ├── CheckLinksStep.swift          # warn on internal links that do not resolve
│   │   │   ├── CopyAssetsStep.swift
│   │   │   ├── ExecuteCommandStep.swift      # run external commands (CSS build, etc.)
│   │   │   ├── MinifyStep.swift              # strip comments/whitespace from HTML and CSS
│   │   │   ├── RenderPagesStep.swift         # frontmatter + engine + markdown → HTML
│   │   │   ├── SitemapStep.swift             # write sitemap.xml (loc, lastmod, hreflang)
│   │   │   ├── OpenSiteStep.swift            # opens a built page (Apple platforms)
│   │   │   └── ServeSiteStep.swift           # serve the site over HTTP (hot reload)
│   │   ├── Support/                          # abstractions over system capabilities
│   │   │   ├── FileSystem.swift              # file-system protocol + local implementation
│   │   │   ├── CommandRunner.swift           # command-execution protocol + Process implementation
│   │   │   ├── Glob.swift                    # glob matching for file paths
│   │   │   ├── FileWatcher.swift             # FSEvents-based file watching
│   │   │   └── StaticFileServer.swift        # HTTP server for the serve step
│   │   ├── Minify/
│   │   │   ├── HTMLMinifier.swift            # comments/whitespace; raw elements untouched
│   │   │   └── CSSMinifier.swift             # comments/whitespace; strings untouched
│   │   ├── Engine/
│   │   │   ├── TemplateEngine.swift          # {{ var }} interpolation, includes, conditionals
│   │   │   ├── Variables.swift               # dot-notation variable context
│   │   │   └── ComponentResolver.swift       # lookup, recursion, cycle detection
│   │   ├── Localization/
│   │   │   ├── Localization.swift            # locale configuration (Site.localize)
│   │   │   └── StringTable.swift             # YAML or .xcstrings strings + fallback
│   │   ├── Frontmatter/Frontmatter.swift     # YAML split + parse (Yams)
│   │   └── Markdown/MarkdownRenderer.swift   # swift-markdown wrapper
│   └── Example/                              # sample site executable (demo, not a product)
│       ├── Main.swift                        # the sample site's pipeline file
│       ├── package.json                      # tailwindcss + @tailwindcss/cli (npm)
│       ├── content/ templates/ components/ assets/ strings/
│       └── build/                            # generated output (gitignored)
└── Tests/Calgary/
    ├── SiteTests.swift
    ├── TestHelpers.swift
    ├── Engine/
    │   ├── ComponentResolverTests.swift
    │   ├── TemplateEngineTests.swift
    │   └── VariablesTests.swift
    ├── Frontmatter/FrontmatterTests.swift
    ├── Localization/StringTableTests.swift
    ├── Markdown/MarkdownRendererTests.swift
    ├── Minify/
    │   ├── CSSMinifierTests.swift
    │   └── HTMLMinifierTests.swift
    ├── Steps/                                # step tests (in-memory file system + mock runner)
    │   ├── CheckLinksStepTests.swift
    │   ├── CopyAssetsStepTests.swift
    │   ├── ExecuteCommandStepTests.swift
    │   ├── MinifyStepTests.swift
    │   ├── OpenSiteStepTests.swift
    │   ├── RenderPagesStepTests.swift
    │   ├── SitemapStepTests.swift
    │   └── ServeSiteStepTests.swift
    └── Support/
        ├── InMemoryFileSystem.swift          # in-memory FileSystem for tests
        ├── MockCommandRunner.swift           # scripted CommandRunner for tests
        └── ProcessCommandRunnerTests.swift   # real-runner tests (echo/sh/pwd, no file writes)
```

## Content model

### Pages (`content/*.md`)

Markdown with YAML frontmatter:

```markdown
---
template: home
variables:
  title: Blue Turtle Canada
---

Hi, welcome to {{ title }}!

{% include "components/hero" %}
```

### Localization

Declared in the pipeline with `Site.localize(defaultLocale:locales:strings:)`. A page whose file name ends in `.<locale>.md` for a declared non-default locale is a translation, written under a `/<locale>/` subfolder in the output (the default locale stays at the root). Strings come from per-locale YAML files or an Xcode `.xcstrings` catalog (pointed at by `strings:`), exposed to templates and components as `{{ strings.… }}`, falling back to the default locale. A string value may contain `{{ … }}` placeholders, resolved against the page's variables (including other strings) when the string is used.

HTML pages are locale-neutral: a default-locale `page.html` is also rendered for every other declared locale (its strings and variables pick up each locale) and written under each `/<locale>/` subfolder, unless an explicit `page.<locale>.html` or `page.<locale>.md` translation exists, in which case that file takes precedence. A default-locale markdown page without a translation renders only for the default locale, and the build reports a warning for each missing locale.

### Templates (`templates/*.html`)

HTML with slots:

```html
<!doctype html>
<html>
<head><title>{{ title }}</title><link rel="stylesheet" href="/css/site.css"></head>
<body>
  {% include "components/header" %}
  <main>{{ content }}</main>
  {% include "components/footer" %}
</body>
</html>
```

### Components (`components/*`)

Markdown (`.md`) or raw HTML (`.html`) partials. They may use variables and include other components. Resolution order: `hero.md` → `hero.html` → `hero` (no extension).

### Template syntax

- `{{ variable }}` — interpolation (dot notation supported: `{{ site.name }}`)
- `{% include "path" %}` — component/template include
- `{% include "path" key="value" %}` — include with variables; arguments are visible inside the component (and its nested includes) and shadow same-named outer variables
- `{% include "path" key={{ variable }} %}` — include with a variable argument; the value is resolved from the current context and keeps its type
- `{% if condition %} … {% else %} … {% endif %}` — basic conditional: a bare variable (truthiness; a missing variable is false) or a `==`/`!=` comparison of quoted strings, numbers, or variables; `else` is optional, nesting is supported, and a missing variable in a comparison fails the build
- `{% for item in items %} … {% else %} … {% endfor %}` — loop over a list; the item is available as `{{ item }}` (dot notation for map items), the optional `else` branch renders when the list is empty, and a missing or non-list collection fails the build
- `strings.…` values may contain `{{ … }}` placeholders, resolved against the page's variables when the string is used; a placeholder that names a missing variable fails the build, as does a string that refers to itself, directly or indirectly. Only the `strings` namespace is expanded; other variable values pass through literally

Single-brace shorthand (`{title}`, `{components/hero}`) was considered but rejected: single braces collide with markdown, JSON, and CSS in real content. If the exact shorthand is ever wanted, it is a one-regex change in `TemplateEngine`.

## Pipeline file (the user-facing API)

This is the API downstream projects use. The file below is the *sample site's* pipeline; a downstream project writes its own equivalent in its own executable target, pointing at its own content.

```swift
// File: Sources/Example/Main.swift (sample site)
import Calgary
import Foundation

@main
struct Main {
    static func main() throws {
        // The sample site's files (content, templates, components, assets)
        // live in this directory, so the site's root is here rather than
        // the package root.
        let site = Site(
            name: "Blue Turtle Canada",
            source: "content",
            output: "build",
            root: URL(fileURLWithPath: "Sources/Example")
        )
        .copyAssets(from: "assets")
        // Build the site's CSS with Tailwind. `--yes` lets npx install
        // the CLI on first run without an interactive prompt.
        .executeCommand(
            "npx",
            arguments: ["--yes", "@tailwindcss/cli",
                        "-i", "assets/css/input.css",
                        "-o", "build/css/site.css"],
            input: "assets/css/input.css",
            output: "build/css/site.css"
        )
        .registerTemplates(in: "templates")
        .registerComponents(in: "components")
        .renderPages()
        .minify()
        .generateSitemap(baseUrl: "https://example.com")
        .open("index.html")

        do {
            try site.build()
            print("Build complete: \(site.outputDirectory.path)")
        } catch {
            print("Build failed: \(error)")
            exit(1)
        }
    }
}
```

## Library design

- **Public API surface**: `Site` and its builder methods (plus `build()`) are the public API. `BuildStep`, `BuildError`, `FileSystem`, `LocalFileSystem`, `CommandRunner`, `CommandResult`, `ProcessCommandRunner`, and `Variable` (the value type of `Site`'s `templateVariables`) are also public so downstream projects can write custom steps and tests. Everything else — engine, frontmatter, steps — stays `internal`.
- **Path resolution**: the `Site` API takes relative paths (`source: "content"`, `output: "build"`); they resolve against `root`, which defaults to the current working directory (the consumer's project root when they run their executable).
- **Sample is not API**: the `Example` executable and the demo content directories exist to demonstrate and integration-test the library; they are not shipped as a product and must not be treated as part of the public API.

## Per-page render flow

1. Read the page, split frontmatter (Yams) → `template`, `date`, variables.
2. Merge variables: built-ins (`site.name`, `site.year` (the current year), `site.pages`, `page.url`, `page.date` when declared; `page.canonical` when the site declares a `baseUrl`; `page.locale`, `site.defaultLocale`, `page.alternates` when localized) + the site's `templateVariables` under `site` (overriding built-ins) + frontmatter (frontmatter wins) + the page's locale strings under `strings` (when localized). `site.pages` is a list of every page's `title`, `url`, `locale`, and (when declared) `date`, built once before any page renders.
3. Evaluate `{% for %}` loops and `{% if %}` conditionals, then resolve `{% include %}`s recursively. Markdown components render to HTML first, then pass through the template engine (so components can nest and use variables). Cycle detection via a resolution stack.
4. Render remaining markdown → HTML via swift-markdown, with smart punctuation disabled so quotes and template tags pass through literally.
5. Inject as `{{ content }}` into the template, interpolate, write output. Path mirrors source: `blog/post.md` → `build/blog/post.html`.
6. When localized, a default-locale HTML page is re-rendered for every declared locale that has no explicit translation file (output under `/<locale>/`); a default-locale markdown page with a missing translation produces a warning instead.

## Dependencies

| Package | Why |
|---|---|
| `swiftlang/swift-markdown` | GFM markdown → HTML, Apple-maintained |
| `jpsim/Yams` | Frontmatter YAML |

The sample site additionally needs Node: `tailwindcss` and `@tailwindcss/cli` are declared in `Sources/Example/package.json`. After cloning, run `npm install` in `Sources/Example` once; the pipeline then runs the CLI via `npx`.

Deliberately **no** Stencil/Handlebars: a custom engine with interpolation, includes, conditionals, and loops is a few hundred lines, matches the syntax exactly, and avoids a full engine we'd only use 10% of.

## Working in this repo

- **Build**: the `Calgary-Package` Xcode scheme, or `swift build`.
- **Test**: `swift test` (or the scheme's test action). Tests use the swift-testing framework and run against `InMemoryFileSystem`/`MockCommandRunner`; `ProcessCommandRunnerTests` exercise the real runner with harmless commands.
- **Run the sample**: `swift run Example` from the package root (requires the one-time `npm install` above; the sample resolves its content relative to the current working directory). It rebuilds `Sources/Example/build/` from scratch and opens `index.html` in a browser.
- `build/` and `node_modules/` are gitignored.

## Conventions

- Swift 6 language mode, `async/await` over Combine, `@MainActor` for UI-bound code (n/a for this CLI, but keep types `Sendable`-friendly).
- Unit tests use the **Testing** framework (`import Testing`), not XCTest.
- Naming: PascalCase for types, camelCase for properties/methods; 4-space indentation.
- No force unwrapping; avoid adding dependencies beyond the table above.
