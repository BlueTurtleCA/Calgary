//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// ComponentResolver.swift
//

import Foundation

/// Resolves `{% include %}` paths to component content.
///
/// Include paths are relative to the site's root (for example,
/// "components/hero"). A path without an extension is tried in order as
/// the `.md` variant, the `.html` variant, and a file with the literal
/// name: "components/hero" resolves to "components/hero.md" if it exists,
/// otherwise to "components/hero.html", otherwise to a file literally
/// named "components/hero".
struct ComponentResolver: Sendable {
    private let root: URL
    private let fileSystem: any FileSystem

    init(root: URL, fileSystem: any FileSystem) {
        self.root = root
        self.fileSystem = fileSystem
    }

    /// Resolves `path` to the component's content.
    ///
    /// - Parameters:
    ///   - path: The include path, relative to the site's root.
    ///   - stack: The resolved component file paths currently being rendered,
    ///     for cycle detection.
    /// - Returns: The component's content, its resolved file path, and
    ///   whether the component is markdown.
    func resolve(_ path: String, stack: [String]) throws -> (content: String, resolvedPath: String, isMarkdown: Bool) {
        let base = root.appendingPathComponent(path)
        let candidates: [URL]
        if path.hasSuffix(".md") || path.hasSuffix(".html") {
            candidates = [base]
        } else {
            candidates = [
                base.appendingPathExtension("md"),
                base.appendingPathExtension("html"),
                base,
            ]
        }
        for candidate in candidates where fileSystem.fileExists(atPath: candidate.path) {
            guard !stack.contains(candidate.path) else {
                throw TemplateError.cyclicInclude(stack + [path])
            }
            let data = try fileSystem.read(contentsOf: candidate)
            return (String(data: data, encoding: .utf8) ?? "", candidate.path, candidate.path.hasSuffix(".md"))
        }
        throw TemplateError.componentNotFound(path)
    }
}
