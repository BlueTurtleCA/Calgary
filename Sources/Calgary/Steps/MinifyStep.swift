//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// MinifyStep.swift
//

import Foundation

/// A build step that minifies the site's output.
///
/// Files matching `glob` (relative to the output directory) are rewritten
/// in place: HTML files have their comments removed and their whitespace
/// collapsed, and CSS files have their comments removed and their
/// whitespace collapsed. The contents of raw HTML elements (`<script>`,
/// `<style>`, `<textarea>`, `<pre>`, and `<code>`) and of CSS strings are
/// left untouched.
///
/// Because the step rewrites files in the output directory, it runs after
/// the steps that produce them:
///
/// ```swift
/// site.copyAssets(from: "assets")
///     .renderPages()
///     .minify()
/// ```
///
/// JavaScript is not minified: a file the glob matches that is not `.html`
/// or `.css` is skipped with a warning. Run a real minifier with
/// `executeCommand` if a site needs JS minification.
struct MinifyStep: BuildStep {
    /// The glob of output files to minify, relative to the output
    /// directory.
    let glob: String

    init(glob: String = "**/*.{html,css}") {
        self.glob = glob
    }

    var name: String {
        "Minify files matching '\(glob)'"
    }

    func run(site: Site) throws {
        let fileSystem = site.fileSystem
        let outputDirectory = site.outputDirectory

        guard fileSystem.fileExists(atPath: outputDirectory.path) else {
            throw BuildError.missingPath(outputDirectory.path)
        }

        for file in try fileSystem.files(in: outputDirectory) {
            let relative = fileSystem.relativePath(of: file, to: outputDirectory)
            guard Glob.matches(glob, path: relative) else { continue }
            try minify(file, relativeTo: relative, site: site, fileSystem: fileSystem)
        }
    }

    private func minify(_ file: URL, relativeTo relative: String, site: Site, fileSystem: any FileSystem) throws {
        let data = try fileSystem.read(contentsOf: file)
        guard let text = String(data: data, encoding: .utf8) else {
            site.warn("skipped '\(relative)': not valid UTF-8")
            return
        }

        let minified: String
        if relative.hasSuffix(".html") {
            minified = HTMLMinifier.minify(text)
        } else if relative.hasSuffix(".css") {
            minified = CSSMinifier.minify(text)
        } else {
            site.warn("skipped '\(relative)': only .html and .css files are minified")
            return
        }

        guard minified != text else { return }
        try fileSystem.write(Data(minified.utf8), to: file)
    }
}
