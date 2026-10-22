# Calgary

A static site generator where the build pipeline is Swift code.

Calgary is a Swift package with a small library for building static sites. Your content is plain files — markdown pages, HTML templates, and markdown or HTML components. Your build is an executable you write: a few lines of Swift that declare the steps — copy assets, build CSS, render pages, open the result.

- **Not Ignite** — HTML is not generated from Swift code; Swift only orchestrates the build.
- **Not Hugo/Jekyll** — there is no config file; the pipeline is Swift code in your repo.
- **Files** are what a writer edits. **Swift** is how the site is assembled.

## Requirements

- Swift 6.4 or later
- Node.js and npm, only if your pipeline runs external commands (the sample builds its CSS with Tailwind)
- macOS for the `open` step; the rest of the library is platform-agnostic

## Getting started

Add Calgary to your package:

```swift
dependencies: [
    .package(url: "https://github.com/BlueTurtleCA/Calgary.git", from: "0.1.0"),
]
```

Create an executable target that depends on the `Calgary` product, and write your pipeline:

```swift
import Calgary

@main
struct Main {
    static func main() throws {
        let site = Site(name: "My Site", source: "content", output: "build")
            .copyAssets(from: "assets")
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()
            .open("index.html")

        try site.build()
    }
}
```

Then lay out your content:

```
my-site/
├── content/            # markdown pages
│   └── index.md
├── templates/          # HTML templates
│   └── home.html
├── components/         # markdown or HTML partials
│   └── hero.html
└── assets/             # files copied to the output as-is
    └── css/
```

Run the executable from your project root. The `build/` directory is recreated from scratch on every build, and `index.html` opens in your browser.

## Content model

### Pages

Markdown files with YAML frontmatter:

```markdown
---
template: home
date: 2026-01-01
variables:
  title: Blue Turtle Canada
---

Hi, welcome to {{ title }}!

{% include "components/hero" %}
```

- `template` (required) — the template to render the page with.
- `date` (optional) — exposed as `{{ page.date }}`.
- `variables` (optional) — a map of values exposed to the page and its components.

The output path mirrors the source path: `content/blog/post.md` → `build/blog/post.html`.

### Templates

HTML files in your templates directory. A page's `template:` key selects one by name (`home` → `home.html`). The rendered page body is available as `{{ content }}`:

```html
<!doctype html>
<html lang="en">
<head><title>{{ title }}</title></head>
<body>
  {% include "components/header" %}
  <main>{{ content }}</main>
  {% include "components/footer" %}
</body>
</html>
```

### Components

Markdown (`.md`) or raw HTML (`.html`) partials in your components directory. They may use variables and include other components. An include without an extension resolves in order: `hero.md` → `hero.html` → `hero`.

Markdown components are rendered to HTML first, then pass through the template engine, so they can nest and use variables just like HTML components.

### Template syntax

- `{{ variable }}` — interpolation; dot notation supported (`{{ site.name }}`)
- `{% include "path" %}` — include a component (or template)
- `{% include "path" key="value" %}` — include with variables; the arguments are visible inside the component (and its nested includes) and shadow same-named outer variables

Built-in variables: `site.name`, `page.url`, and `page.date` (when declared). When the site is localized, pages also get `page.locale`, `site.defaultLocale`, and `page.alternates` (see [Localization](#localization)). Variables from a page's frontmatter override built-ins.

Site-wide variables can be declared in the pipeline and are exposed under the `site` namespace:

```swift
let site = Site(
    name: "My Site",
    templateVariables: ["year": .string("2026")]
)
```

`{{ site.year }}` then renders `2026` on every page. Values are `Variable`s — strings, numbers, booleans, lists, or nested maps — so computed or fetched values (a year, a scraped headline) can flow straight into templates.

## Localization

A site can be published in several locales. Declare them in the pipeline with `localize`:

```swift
let site = Site(name: "My Site", source: "content", output: "build")
    .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "strings")
    .registerTemplates(in: "templates")
    .registerComponents(in: "components")
    .renderPages()
```

### Translated pages

A page is a translation when its file name ends in `.<locale>.md` for a declared non-default locale. Translations are written under a subfolder named after the locale; the default locale stays at the output root:

```
content/index.md           →  build/index.html
content/index.fr-fr.md     →  build/fr-fr/index.html
content/blog/post.md       →  build/blog/post.html
content/blog/post.fr-fr.md →  build/fr-fr/blog/post.html
```

A file whose suffix is not a declared locale is an ordinary page, not a translation.

### String files

Shared UI strings come from one of two sources, both pointed at by `strings:`: a directory of per-locale YAML files, or a single Xcode string catalog.

**Per-locale YAML files** — one file per locale, named `<locale>.yaml`:

```yaml
# strings/en.yaml
nav:
  home: Home
  about: About
```

```yaml
# strings/fr-fr.yaml
nav:
  home: Accueil
```

**An Xcode string catalog** — a `.xcstrings` file holding every locale, editable in Xcode's String Catalog editor:

```json
{
    "sourceLanguage": "en",
    "strings": {
        "nav.home": {
            "localizations": {
                "en": { "stringUnit": { "state": "translated", "value": "Home" } },
                "fr-FR": { "stringUnit": { "state": "translated", "value": "Accueil" } }
            }
        }
    },
    "version": "1.0"
}
```

```swift
.localize(defaultLocale: "en", locales: ["fr-fr"], strings: "Localizable.xcstrings")
```

In a catalog, keys are flat: a dot in a key becomes a nesting level, so `nav.home` resolves as `{{ strings.nav.home }}`. Locale IDs are matched case-insensitively, so Xcode's `fr-FR` satisfies the site's `fr-fr`. Plural and device variations are not supported; only simple string values are read.

In both cases, the active locale's strings are exposed to templates and components as `{{ strings.… }}` (dot notation). Any key missing in the locale falls back to the default locale, so a translation only needs the keys it changes.

### Built-in variables

When a site is localized, pages also get:

- `page.locale` — the page's locale (for example, `fr-fr`), useful for `<html lang="{{ page.locale }}">`.
- `site.defaultLocale` — the site's default locale.
- `page.alternates` — ready-to-paste `<link rel="alternate" hreflang="…">` tags, one per locale that has a translation of the page, plus an `x-default` tag. Put it in the template's `<head>`:

```html
<head>
    <title>{{ title }}</title>
    {{ page.alternates }}
</head>
```

## The pipeline

A `Site` is a list of steps, run in order by `build()` (which first removes and recreates the output directory):

| Method | What it does |
|---|---|
| `copyAssets(from:)` | Copies the assets directory into the output, preserving relative paths |
| `executeCommand(_:arguments:input:output:)` | Runs an external command with the site root as working directory; the build fails if the declared input is missing or the declared output is not produced |
| `registerTemplates(in:)` | Registers the templates directory (required by `renderPages`) |
| `registerComponents(in:)` | Registers the components directory |
| `localize(defaultLocale:locales:strings:)` | Configures the site's locales and strings source (YAML directory or `.xcstrings` catalog); translations render under `/<locale>/` |
| `renderPages(glob:)` | Renders every page matching the glob (default `**/*.md`) into its template |
| `open(_:)` | Opens a built page in the default browser (Apple platforms) |
| `serve(port:hotReload:)` | Serves the built site over HTTP and keeps the process running; with hot reload (the default), a file change rebuilds the site in place and reloads the browser |
| `addStep(_:)` | Adds a custom step |

### Custom steps

Conform a type to `BuildStep` and add it to the pipeline:

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

Failures surface as `BuildError` (missing paths, failed commands, missing configuration), which is what `build()` throws.

## The sample site

This repo includes a complete sample — the "Blue Turtle Canada" demo — in `Sources/Example/`. It demonstrates the full pipeline, including a Tailwind CSS build via `executeCommand`, a markdown component, and localization (a French translation of the home page).

```sh
cd Sources/Example && npm install   # once, for the Tailwind CLI
cd ../..
swift run Example                   # builds and opens the site
```

The sample resolves its content relative to the current working directory, so run `swift run Example` from the package root.

Xcode's run button works too: when a command is missing from the minimal `PATH` Xcode launches with, `ProcessCommandRunner` falls back to the common install locations for Node.js and other command-line tools (Homebrew, nvm, Volta, asdf, mise).

## Development

- `swift test` runs the test suite (swift-testing). Tests run against an in-memory file system and a mock command runner, so they never touch your content.
- See `AGENTS.md` for contributor and AI-agent guidance.

## Design notes

- **No full template engine.** Interpolation + includes is a small custom engine; `{% if %}`/`{% for %}` would be a contained extension if ever needed.
- **Smart punctuation is disabled** when rendering markdown, so quotes and template tags pass through literally.
- **No config file.** If it isn't in the pipeline file, it isn't part of the build.
