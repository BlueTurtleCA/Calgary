<p align="center">
  <img src="assets/calgary.jpg" width="256" alt="Calgary">
</p>

# Calgary

A static site generator where the build pipeline is Swift code.

Calgary is a Swift package with a small library for building static sites. Your content is plain files — markdown pages, HTML templates, and markdown or HTML components. Your build is an executable you write: a few lines of Swift that declare the steps — copy assets, build CSS, render pages, open the result.

- **Not Ignite** — HTML is not generated from Swift code; Swift only orchestrates the build.
- **Not Hugo/Jekyll** — there is no config file; the pipeline is Swift code in your repo.
- **Files** are what a writer edits. **Swift** is how the site is assembled.

## Requirements

- Swift 6.4 or later
- Node.js and npm, only if your pipeline runs external commands (the sample builds its CSS with Tailwind)
- The `open` and `serve` steps open a browser (best-effort: on non-Apple platforms the launch goes through `xdg-open` or `cmd /c start`); the rest of the library works on macOS, Linux, and Windows

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

- `template` — the template to render the page with. Required for markdown pages outside a [collection](#collections); a collection's pages may omit it and use the collection's template.
- `date` (optional) — exposed as `{{ page.date }}`; sorts a collection's index, newest first.
- `variables` (optional) — a map of values exposed to the page and its components.
- **Any other top-level key is a variable** — `title: Hello` renders as `{{ title }}` just like an entry under `variables:` (a top-level key wins over a same-named `variables` entry). This is how a post carries a `description` or `image` that its collection's index can show.

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
- `{% include "path" key={{ variable }} %}` — include with a variable argument; the value is resolved from the current context and keeps its type
- `{% if condition %} … {% else %} … {% endif %}` — conditional; `else` is optional and nesting is supported
- `{% for item in items %} … {% else %} … {% endfor %}` — loop over a list; the item is available as `{{ item }}` (dot notation for map items), and the optional `else` branch renders when the list is empty
- `{% for item in items where field operator value %}` — a loop may carry a `where` filter that excludes items whose field does not match; the operator is `==`, `!=`, `startsWith`, `endsWith`, or `contains`, the value is a quoted string, a number, or a variable, and an item with a missing field is excluded

A condition is a bare variable (a truthiness check) or a `==`/`!=` comparison. Operands are quoted strings, numbers, or variables:

```html
{% if page.locale == "en" %}
  <p>English version</p>
{% else %}
  <p>Other locale</p>
{% endif %}
```

A bare variable is an existence check: a missing variable is false. In a comparison, a missing variable fails the build, as do an unclosed `{% if %}` and a stray `{% else %}` or `{% endif %}`. A `{% for %}` collection must be a list (a missing or non-list variable fails the build), as do an unclosed `{% for %}` and a stray `{% endfor %}`.

Built-in variables: `site.name`, `site.year` (the current year, computed at build time), `page.url`, and `page.date` (when declared). When the site is created with a `baseUrl`, pages also get `page.canonical` — the page's absolute URL, ready to paste into `<link rel="canonical">`. When the site is localized, pages also get `page.locale`, `site.defaultLocale`, and `page.alternates` (see [Localization](#localization)). Variables from a page's frontmatter override built-ins.

`site.pages` is a list of the site's pages, each with the page's frontmatter variables plus `title`, `url`, `locale`, and (when declared) `date`. A page's `title` is its `title` frontmatter variable, falling back to the file name. Use it with `{% for %}` to build listing pages and navigation:

```html
{% for page in site.pages %}
  <a href="{{ page.url }}">{{ page.title }}</a>
{% endfor %}
```

Site-wide variables can be declared in the pipeline and are exposed under the `site` namespace:

```swift
let site = Site(
    name: "My Site",
    templateVariables: ["year": .string("2026")]
)
```

`{{ site.year }}` then renders `2026` on every page. Values are `Variable`s — strings, numbers, booleans, lists, or nested maps — so computed or fetched values (a year, a scraped headline) can flow straight into templates.

## Collections

A collection is a directory of pages that share a template and get a generated index, optionally paginated — a blog, a gallery, a docs section. Declare it in the pipeline:

```swift
let site = Site(name: "My Site", source: "content", output: "build")
    .addCollection(name: "blog", source: "blog", template: "post", index: "blog-index", paginate: 2)
    .registerTemplates(in: "templates")
    .registerComponents(in: "components")
    .renderPages()
```

- The collection's pages (here, `content/blog/*.md`) render like any other page, using the collection's `template` when their frontmatter declares none.
- After the pages render, the collection's `index` template renders once per page of the collection: `build/blog/index.html` (and `build/blog/page/2/index.html`, … when `paginate:` is set). The index template renders with `items` (the pages on this page), `total`, `count`, `number`, `pageCount`, `hasPrevious`, `hasNext`, and (when present) `previousUrl` and `nextUrl`, plus the usual `site` and `page` built-ins.
- The collection's pages are exposed to every template as `{{ site.<name> }}` (here, `{{ site.blog }}`), sorted by `date` descending (undated pages last), each entry carrying the page's `title`, `url`, `locale`, `date`, and every frontmatter variable — so the index can show a post's `description` without extra plumbing.
- A site can have several collections (a blog and a gallery, for example); each is exposed under its own name and renders its index under its own directory. Collection names must be unique and must not collide with a built-in `site` variable.
- There cannot be a page at the collection's root (`content/blog/index.md`): the generated index owns that path.
- When the site is localized, the collection lists the pages of the current locale: `{{ site.<name> }}` on an `fr-fr` page shows the French translations of the posts, each with its French `url`. The index renders once per declared locale that has at least one translated page — `build/fr-fr/blog/index.html` and its pagination pages — with the locale's items, locale-prefixed `page.url`/`page.canonical`/`page.alternates`/pagination URLs, the locale's strings, and `page.locale` set; a locale with no translated pages is skipped with a warning. A missing translation of a collection page itself is not warned about (a blog does not translate every post).

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

A string value may contain `{{ … }}` placeholders, resolved against the page's variables when the string is used — so a translation can carry a value that only the build knows:

```yaml
# strings/en.yaml
footer:
  copyright: Copyright {{ site.year }} My Company. All rights reserved.
```

```html
<p>{{ strings.footer.copyright }}</p>
```

renders `Copyright 2026 My Company. All rights reserved.` (with the current year). Placeholders resolve against the same variables as the template — `site.year`, frontmatter variables, or other strings — and a placeholder that names a missing variable fails the build, as does a string that refers to itself, directly or indirectly. Only values in the `strings` namespace are expanded; every other variable value passes through literally.

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
| `executeCommand(_ invocation:windows:macos:linux:input:output:)` | Runs an external command, selecting the invocation declared for the platform the build runs on ([Per-platform commands](#per-platform-commands)) |
| `registerTemplates(in:)` | Registers the templates directory (required by `renderPages`) |
| `registerComponents(in:)` | Registers the components directory |
| `localize(defaultLocale:locales:strings:)` | Configures the site's locales and strings source (YAML directory or `.xcstrings` catalog); translations render under `/<locale>/` |
| `addCollection(name:source:template:index:paginate:)` | Adds a collection of pages that share a template and get a generated index, optionally paginated; the pages are exposed to templates as `{{ site.<name> }}` |
| `renderPages(glob:)` | Renders every page matching the glob (default `**/*.md`) into its template |
| `generateSitemap(baseUrl:)` | Writes `sitemap.xml` of every built page under the base URL (defaulting to the site's `baseUrl`), with a `<lastmod>` per page (frontmatter `date`, falling back to file modification time) and, for localized sites, `hreflang` alternates |
| `open(_:)` | Opens a built page in the default browser |
| `serve(port:hotReload:)` | Serves the built site over HTTP and keeps the process running; with hot reload (the default), a file change rebuilds the site in place and reloads the browser |
| `addStep(_:)` | Adds a custom step |

### Per-platform commands

A command that differs by platform is declared in one step, without `#if` in the pipeline file. Each invocation is a `CommandInvocation` (an executable and its arguments); the first invocation runs on every platform that has no override:

```swift
let site = Site(name: "My Site", source: "content", output: "build")
    .executeCommand(
        CommandInvocation("npx", arguments: ["--yes", "@tailwindcss/cli", "-i", "assets/css/input.css", "-o", "build/css/site.css"]),
        windows: CommandInvocation("npx.cmd", arguments: ["--yes", "@tailwindcss/cli", "-i", "assets/css/input.css", "-o", "build/css/site.css"]),
        input: "assets/css/input.css",
        output: "build/css/site.css"
    )
```

On Windows, `ProcessCommandRunner` resolves command names the way `cmd` does: for a bare name it tries the `PATHEXT` extensions (`.COM`, `.EXE`, `.BAT`, `.CMD`, …) in `PATH` and in the runner's additional search directories, so a command named `npx` finds npm's `npx.cmd` shim. An override is therefore only needed when the executable or its arguments genuinely differ. The child's `PATH` is prepended with the resolved executable's directory (`;`-separated on Windows) so the command can find sibling binaries — `npx` finds `node` that way.

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

This repo includes a complete sample — the "Blue Turtle Canada" demo — in `Sources/Example/`. It demonstrates the full pipeline, including a Tailwind CSS build via `executeCommand`, a markdown component, localization (a French translation of the home page and the blog posts), and a paginated blog collection.

```sh
cd Sources/Example && npm install   # once, for the Tailwind CLI
cd ../..
swift run Example                   # builds and opens the site
```

The sample resolves its content relative to the current working directory, so run `swift run Example` from the package root.

Xcode's run button works too: when a command is missing from the minimal `PATH` Xcode launches with, `ProcessCommandRunner` falls back to the common install locations for Node.js and other command-line tools (Homebrew, nvm, Volta, asdf, and mise on macOS and Linux; the per-user Node.js installer, winget, npm's global directory, volta, scoop, and nvm-windows on Windows).

## Development

- `swift test` runs the test suite (swift-testing). Tests run against an in-memory file system and a mock command runner, so they never touch your content.
- See `AGENTS.md` for contributor and AI-agent guidance.

## Design notes

- **No full template engine.** Interpolation, includes, conditionals, and loops are a small custom engine.
- **Smart punctuation is disabled** when rendering markdown, so quotes and template tags pass through literally.
- **No config file.** If it isn't in the pipeline file, it isn't part of the build.

## License

MIT — see [LICENSE](LICENSE).
