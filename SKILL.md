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
├── content/                    # markdown pages
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
        let site = Site(name: "My Site", source: "content", output: "build")
            .copyAssets(from: "assets")
            .registerTemplates(in: "templates")
            .registerComponents(in: "components")
            .renderPages()
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

All paths are relative to the current working directory, so run the executable from the project root.

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
- Built-in variables: `site.name`, `page.url`, `page.date` (when declared); when the site is localized, also `page.locale`, `site.defaultLocale`, and `page.alternates`. Frontmatter variables override built-ins.

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

## Pipeline steps

| Method | What it does |
|---|---|
| `copyAssets(from:)` | Copies the assets directory into the output, preserving relative paths |
| `executeCommand(_:arguments:input:output:)` | Runs an external command with the project root as working directory; fails the build if the declared input is missing or the declared output is not produced |
| `registerTemplates(in:)` | Registers the templates directory (required by `renderPages`) |
| `registerComponents(in:)` | Registers the components directory |
| `localize(defaultLocale:locales:strings:)` | Configures locales and the strings source (YAML directory or `.xcstrings` catalog); translations render under `/<locale>/` |
| `renderPages(glob:)` | Renders every page matching the glob (default `**/*.md`) into its template |
| `open(_:)` | Opens a built page in the default browser (Apple platforms) |
| `addStep(_:)` | Adds a custom step |

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

- Relative paths in `Site(...)` resolve against the current working directory (or an explicit `root:`), so run the pipeline from the project root.
- `renderPages` requires `registerTemplates(in:)` to have been called.
- Markdown is rendered with smart punctuation disabled — straight quotes and `{% include %}` tags pass through literally.
- `open(_:)` is a no-op off Apple platforms.
- A `.<locale>.md` page is a translation only when that locale is declared in `localize`; otherwise it's an ordinary page.
- A site has one strings source: a directory of YAML files or a `.xcstrings` catalog, not both.
- Add `build/` (and `node_modules/`, if using Tailwind) to `.gitignore`.

For a complete working example, see the sample site in the Calgary repo (`Sources/Example/`).
