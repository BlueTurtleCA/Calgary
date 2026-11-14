//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// Main.swift
//

import Calgary
import Foundation

// The sample site's build pipeline. Downstream projects write their own
// equivalent of this file in an executable target: plain Swift code that
// declares the build steps.

@main
struct Main {
    static func main() throws {
        // The sample site's files (content, templates, components, assets)
        // live in this directory, so the site's root is here rather than
        // the package root. Anchoring to this file's location (resolved at
        // compile time) means the sample builds from any working directory,
        // including Xcode's run button, which runs the executable from
        // DerivedData rather than the package root.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let site = Site(
            name: "Blue Turtle Canada",
            source: "content",
            output: "build",
            root: root,
            baseUrl: "https://example.com"
        )
        .localize(defaultLocale: "en", locales: ["fr-fr"], strings: "strings")
        // The blog: the posts in content/blog render with the `post`
        // template, and the `blog-index` template renders the index —
        // paginated two posts per page.
        .addCollection(
            name: "blog",
            source: "blog",
            template: "post",
            index: "blog-index",
            paginate: 2
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
        // The base URL comes from the Site, so the step needs no argument.
        .generateSitemap()
        .checkLinks()

        // The sample opens the built file by default, so the build always
        // finishes. Pass --serve to serve the site over HTTP instead, which
        // is how absolute paths like /css/site.css resolve in production.
        if CommandLine.arguments.contains("--serve") {
            site.serve()
        } else {
            site.open("index.html")
        }

        do {
            try site.build()
            print("Build complete: \(site.outputDirectory.path)")
        } catch {
            print("Build failed: \(error)")
            exit(1)
        }
    }
}
