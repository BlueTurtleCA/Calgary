---
name: calgary
description: How to build a static site with Calgary, the Swift static site generator (https://github.com/BlueTurtleCA/Calgary). Use when asked to scaffold or extend a website with Calgary, or when working in a project that depends on the Calgary package.
---

# Building a site with Calgary

Calgary is a static site generator as a Swift package. Content is plain files — markdown pages, HTML templates, and markdown/HTML components. The build is Swift code: a `Site` configured with daisy-chained steps and run with `build()`. There is no config file; the pipeline file is the build.

## Prerequisites

- Swift 6.4 or later
- Node.js + npm, only if the site builds CSS with Tailwind (see "CSS with Tailwind")

## 1. Create the package and add Calgary

In an empty directory:

```sh
swift package init --type executable
```

In `Package.swift`, add the dependency and point the executable target at the `Calgary` product:

```swift
dependencies: [
    .package(url: "https://github.com/BlueTurtleCA/Calgary.git", from: "0.1.0"),
],
targets: [
    .executableTarget(
        name: "MySite",
        dependencies: [.product(name: "Calgary", package: "Calgary")]
    ),
]
```

## 2. Lay out the content

```
project/
├── Package.swift
├── Sources/MySite/Main.swift   # the build pipeline
├── content/                    # markdown or HTML pages
│   └── index.md
├── templates/                  # HTML templates
│   └── home.html
├── components/                 # markdown or HTML partials
│   └── header.html
├── strings/                    # per-locale YAML strings (optional)
│   └── en.yaml
└── assets/                     # copied to the output as-is
    └── css/
```

## 3. Write the pipeline

`Sources/MySite/Main.swift`:

```swift
import Calgary
import Foundation

@main
struct Main {
    static func main() throws {
        // Anchor the site's root to this file's location (resolved at
        // compile time) so the build works from any working directory —
        // including Xcode's run button, which runs the executable from
        // DerivedData rather than the project root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Sources/MySite
            .deletingLastPathComponent() // project root
        let site = Site(name: "My Site", source: "content", output: "build", root: root)
            .copyAssets(from: "assets")
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()
            .checkLinks()
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

All paths are relative to the site's root. Because the root is anchored to the pipeline file, the build works from any working directory — the terminal or Xcode's run button.

## 4. Write the content

### Page — `content/index.md`

Markdown with YAML frontmatter:

```markdown
---
template: home
date: 2026-01-01
variables:
  title: My Site
---

Hi, welcome to {{ title }}!

{% include "components/header" %}
```

- `template` (required) — selects the template by name (`home` → `templates/home.html`).
- `date` (optional) — exposed as `{{ page.date }}`.
- `variables` (optional) — values exposed to the page and its components.
- The output path mirrors the source path: `content/blog/post.md` → `build/blog/post.html`.

### Template — `templates/home.html`

HTML with `{{ content }}` as the slot for the rendered page body:

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>{{ title }}</title></head>
<body>
  {% include "components/header" %}
  <main>{{ content }}</main>
</body>
</html>
```

### Components — `components/*`

Markdown (`.md`) or raw HTML (`.html`) partials. They may use variables and include other components. An include without an extension resolves in order: `header.md` → `header.html` → `header`. Markdown components are rendered to HTML first, then pass through the template engine, so they nest and use variables just like HTML components.

### Template syntax

- `{{ variable }}` — interpolation; dot notation supported (`{{ site.name }}`)
- `{% include "path" %}` — include a component (or template)
- `{% include "path" key="value" %}` — include with variables; the arguments are visible inside the component (and its nested includes) and shadow same-named outer variables
- `{% include "path" key={{ variable }} %}` — include with a variable argument; the value is resolved from the current context and keeps its type
- `{% if condition %} … {% else %} … {% endif %}` — conditional; `else` is optional and nesting is supported
- `{% for item in items %} … {% else %} … {% endfor %}` — loop over a list; the item is available as `{{ item }}` (dot notation for map items), and the optional `else` branch renders when the list is empty

A condition is a bare variable (a truthiness check; a missing variable is false) or a `==`/`!=` comparison of quoted strings, numbers, or variables:

```html
{% if page.locale == "en" %}
  <p>English version</p>
{% else %}
  <p>Other locale</p>
{% endif %}
```

In a comparison, a missing variable fails the build, as do an unclosed `{% if %}` and a stray `{% else %}` or `{% endif %}`. A `{% for %}` collection must be a list (a missing or non-list variable fails the build), as do an unclosed `{% for %}` and a stray `{% endfor %}`.

- Built-in variables: `site.name`, `site.pages`, `page.url`, `page.date` (when declared); when the site is created with a `baseUrl`, also `page.canonical` (the page's absolute URL, for `<link rel="canonical">`); when the site is localized, also `page.locale`, `site.defaultLocale`, and `page.alternates`. Frontmatter variables override built-ins.
- `site.pages` is a list of the site's pages, each with `title`, `url`, `locale`, and (when declared) `date`; a page's `title` falls back to its file name. Use it with `{% for %}` to build listing pages and navigation:

```html
{% for page in site.pages %}
  <a href="{{ page.url }}">{{ page.title }}</a>
{% endfor %}
```

- Site-wide variables: pass `templateVariables:` to `Site(...)` — for example, `templateVariables: ["year": .string("2026")]` renders as `{{ site.year }}` on every page. Values are `Variable`s (strings, numbers, booleans, lists, nested maps), so computed or fetched values (a year, a scraped headline) can flow straight into templates; they override same-named built-ins.

### Localization (optional)

Declare the locales in the pipeline:

```swift
let site = Site(name: "My Site", source: "content", output: "build")
    .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "strings")
    .registerTemplates(in: "templates")
    .registerComponents(in: "components")
    .renderPages()
```

- A page whose file name ends in `.<locale>.md` for a declared non-default locale is a translation, written under a subfolder named after the locale: `content/index.fr-fr.md` → `build/fr-fr/index.html`. The default locale stays at the output root.
- HTML pages are locale-neutral: a default-locale `page.html` is also rendered for every other declared locale, with that locale's strings and variables, and written under each `/<locale>/` subfolder — unless an explicit `page.<locale>.html` or `page.<locale>.md` translation exists, in which case that file takes precedence.
- A default-locale markdown page without a translation renders only for the default locale; the build prints a warning for each missing locale.
- Strings come from a directory of per-locale YAML files (`strings/<locale>.yaml`) or from a single Xcode string catalog (`strings: "Localizable.xcstrings"`). In a catalog, keys are flat and a dot in a key is a nesting level; locale IDs are matched case-insensitively (`fr-FR` satisfies `fr-fr`).
- The active locale's strings are exposed to templates and components as `{{ strings.… }}`, falling back to the default locale for missing keys.
- `page.alternates` is ready-to-paste `<link rel="alternate" hreflang="…">` tags (one per locale that has the page, plus `x-default`); put it in the template's `<head>`.

## 5. Build and verify

```sh
swift run MySite
```

- `build/` is wiped and recreated on every build; steps run in the order they were added.
- The `open` step opens `build/index.html` in a browser on Apple platforms; otherwise inspect the generated HTML directly.
- A failed build throws a `BuildError` whose message names the failing step.
- Warnings (for example, a markdown page with no translation, or an internal link that does not resolve to a built page) are printed when the build finishes; they do not fail the build.

## Pipeline steps

| Method | What it does |
|---|---|
| `copyAssets(from:)` | Copies the assets directory into the output, preserving relative paths |
| `executeCommand(_:arguments:input:output:)` | Runs an external command with the project root as working directory; fails the build if the declared input is missing or the declared output is not produced |
| `registerTemplates(in:)` | Registers the templates directory (required by `renderPages`) |
| `registerComponents(in:)` | Registers the components directory |
| `localize(defaultLocale:locales:strings:)` | Configures locales and the strings source (YAML directory or `.xcstrings` catalog); translations render under `/<locale>/` |
| `renderPages(glob:)` | Renders every page matching the glob (default `**/*.{md,html}`) into its template |
| `minify(glob:)` | Minifies output files matching the glob (default `**/*.{html,css}`): strips HTML and CSS comments and collapses whitespace; raw HTML elements (`<script>`, `<style>`, `<textarea>`, `<pre>`, `<code>`) and CSS strings are untouched |
| `generateSitemap(baseUrl:)` | Writes `sitemap.xml` listing every `.html` file in the output under `baseUrl` (defaulting to the site's `baseUrl`), with a `<lastmod>` per page (frontmatter `date`, falling back to file modification time) and, for localized sites, `hreflang` alternates; run after `renderPages` |
| `checkLinks(glob:)` | Checks the internal `href`s in output files matching the glob (default `**/*.html`): each link is resolved the way the site's server resolves requests, and a warning is reported for each link that does not resolve to a built file; links with a scheme (`https://`, `mailto:`, …), fragment-only links, and anchors on the current page are skipped, and a link to a directory resolves to its `index.html` |
| `open(_:)` | Opens a built page in the default browser (Apple platforms) |
| `addStep(_:)` | Adds a custom step |

`robots.txt` is a plain file, not a step: put it in `assets/` and `copyAssets` ships it.

### Custom steps

```swift
struct MinifyJavaScriptStep: BuildStep {
    var name: String { "Minify JavaScript" }

    func run(site: Site) throws {
        // site.root, site.outputDirectory, site.fileSystem, site.commandRunner
    }
}

let site = Site(name: "My Site")
    .renderPages()
    .addStep(MinifyJavaScriptStep())
```

### CSS with Tailwind (optional)

Declare `tailwindcss` and `@tailwindcss/cli` in a `package.json` at the project root, run `npm install` once, then add a step:

```swift
.executeCommand(
    "npx",
    arguments: ["--yes", "@tailwindcss/cli",
                "-i", "assets/css/input.css",
                "-o", "build/css/site.css"],
    input: "assets/css/input.css",
    output: "build/css/site.css"
)
```

## Gotchas

- Relative paths in `Site(...)` resolve against the site's `root`, which defaults to the current working directory. When the executable is run from Xcode's run button, that is DerivedData, not the project root — pass an explicit `root:` anchored to the pipeline file with `#filePath` (as in the example above).
- `renderPages` requires `registerTemplates(in:)` to have been called.
- Markdown is rendered with smart punctuation disabled — straight quotes and `{% include %}` tags pass through literally.
- `open(_:)` is a no-op off Apple platforms.
- A `.<locale>.md` page is a translation only when that locale is declared in `localize`; otherwise it's an ordinary page.
- A site has one strings source: a directory of YAML files or a `.xcstrings` catalog, not both.
- Add `build/` (and `node_modules/`, if using Tailwind) to `.gitignore`.

For a complete working example, see the sample site in the Calgary repo (`Sources/Example/`).
