//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// MarkdownRenderer.swift
//

import Markdown

/// Renders markdown to HTML using swift-markdown (GFM).
struct MarkdownRenderer: Sendable {
    /// Renders `markdown` to an HTML fragment.
    ///
    /// Smart punctuation is disabled so characters pass through unchanged:
    /// content is data, and template tags like `{% include "path" %}` rely
    /// on literal straight quotes.
    func render(_ markdown: String) -> String {
        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        return HTMLFormatter.format(document)
    }
}
