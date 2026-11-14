//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// CheckLinksStep.swift
//

import Foundation

/// A build step that checks the internal links in the site's output.
///
/// Every `href` in the output files matching `glob` is resolved the way the
/// site's server resolves requests, and the build reports a warning for each
/// link that does not resolve to a built file:
///
/// ```swift
/// site.renderPages()
///     .checkLinks()
/// ```
///
/// Links with a scheme (`https://`, `mailto:`, …), fragment-only links
/// (`#section`), and anchors on the current page are skipped. A link to a
/// directory resolves to that directory's `index.html`, and query strings
/// and percent-encoding are handled.
struct CheckLinksStep: BuildStep {
    /// The glob of output files to check, relative to the output directory.
    let glob: String

    init(glob: String = "**/*.html") {
        self.glob = glob
    }

    var name: String {
        "Check links in '\(glob)'"
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
            try checkLinks(
                in: file,
                relativeTo: relative,
                site: site,
                fileSystem: fileSystem,
                outputDirectory: outputDirectory
            )
        }
    }

    private func checkLinks(
        in file: URL,
        relativeTo relative: String,
        site: Site,
        fileSystem: any FileSystem,
        outputDirectory: URL
    ) throws {
        let data = try fileSystem.read(contentsOf: file)
        guard let html = String(data: data, encoding: .utf8) else {
            site.warn("skipped '\(relative)': not valid UTF-8")
            return
        }

        var seen = Set<String>()
        for href in Self.hrefs(in: html) where seen.insert(href).inserted {
            if Self.resolve(href, from: relative, in: outputDirectory, fileSystem: fileSystem) == .broken {
                site.warn("'\(href)' in '\(relative)' does not resolve to a built page")
            }
        }
    }

    // MARK: Link extraction

    /// The values of every `href` attribute in `html`, in document order.
    private static func hrefs(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        ) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var results: [String] = []
        for match in regex.matches(in: html, range: range) {
            for group in 1...3 {
                let value = match.range(at: group)
                guard value.location != NSNotFound else { continue }
                let start = html.index(html.startIndex, offsetBy: value.location)
                let end = html.index(start, offsetBy: value.length)
                results.append(String(html[start..<end]))
                break
            }
        }
        return results
    }

    // MARK: Link resolution

    /// How an `href` resolves against the site's output.
    private enum LinkResolution {
        /// The link is not a path into the output: it has a scheme (for
        /// example, `https://` or `mailto:`) or is fragment- or query-only.
        case skip
        /// The link is a path into the output and resolves to a built file.
        case resolves
        /// The link is a path into the output but does not resolve to a
        /// built file.
        case broken
    }

    /// How `href` resolves, given that it appears in the page at `page`
    /// (relative to the output directory).
    ///
    /// The resolution mirrors the site's server: the fragment and query
    /// string are ignored, the path is percent-decoded, relative paths
    /// resolve against the page's directory, and a directory resolves to
    /// its `index.html`.
    private static func resolve(
        _ href: String,
        from page: String,
        in outputDirectory: URL,
        fileSystem: any FileSystem
    ) -> LinkResolution {
        var path = href
        if let fragment = path.firstIndex(of: "#") {
            path.removeSubrange(fragment...)
        }
        if let query = path.firstIndex(of: "?") {
            path.removeSubrange(query...)
        }
        guard !path.isEmpty else { return .skip }

        // A link with a scheme points outside the site.
        if let colon = path.firstIndex(of: ":") {
            let scheme = path[..<colon]
            if let first = scheme.first, first.isLetter,
               scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) {
                return .skip
            }
        }

        path = path.removingPercentEncoding ?? path

        // Absolute links resolve against the output root; relative links
        // against the directory of the page they appear in.
        let base = path.hasPrefix("/") ? [] : page.split(separator: "/").dropLast().map(String.init)
        var segments: [String] = []
        for segment in base + path.split(separator: "/").map(String.init) {
            switch segment {
            case "", ".":
                continue
            case "..":
                guard !segments.isEmpty else { return .broken }
                segments.removeLast()
            default:
                segments.append(segment)
            }
        }

        // A link to a directory resolves to its index.html.
        if path.hasSuffix("/") {
            segments.append("index.html")
        }

        let url = outputDirectory.appendingPathComponent(segments.joined(separator: "/"))
        if fileSystem.isDirectory(atPath: url.path) {
            // A directory resolves only when it has an index.html, the way
            // the site's server serves it.
            return fileSystem.fileExists(atPath: url.appendingPathComponent("index.html").path)
                ? .resolves
                : .broken
        }
        return fileSystem.fileExists(atPath: url.path) ? .resolves : .broken
    }
}
