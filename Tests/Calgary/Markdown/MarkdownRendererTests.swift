//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// MarkdownRendererTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("MarkdownRenderer")
struct MarkdownRendererTests {
    private let renderer = MarkdownRenderer()

    /// The HTML formatter appends a trailing newline; trim it for comparisons.
    private func render(_ markdown: String) -> String {
        renderer.render(markdown).trimmingCharacters(in: .newlines)
    }

    @Test("Renders a heading")
    func rendersHeading() {
        #expect(render("## Hello") == "<h2>Hello</h2>")
    }

    @Test("Renders a paragraph")
    func rendersParagraph() {
        #expect(render("Hello, world.") == "<p>Hello, world.</p>")
    }

    @Test("Renders a link")
    func rendersLink() {
        #expect(render("[Calgary](https://example.com)") == "<p><a href=\"https://example.com\">Calgary</a></p>")
    }

    @Test("Renders a fenced code block")
    func rendersFencedCodeBlock() {
        let html = renderer.render("```\nlet x = 1\n```")
        #expect(html.contains("<pre><code>") == true)
        #expect(html.contains("let x = 1") == true)
    }

    @Test("Passes raw HTML blocks through")
    func passesRawHTMLBlocksThrough() {
        let html = renderer.render("<section class=\"hero\">\n  <h2>Hi</h2>\n</section>")
        #expect(html.contains("<section class=\"hero\">") == true)
        #expect(html.contains("<h2>Hi</h2>") == true)
    }

    @Test("Renders a GFM table")
    func rendersGFMTable() {
        let html = renderer.render("| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(html.contains("<table>") == true)
        #expect(html.contains("<th>a</th>") == true)
        #expect(html.contains("<td>1</td>") == true)
    }

    @Test("Keeps straight quotes instead of converting them to smart quotes")
    func keepsStraightQuotes() {
        #expect(render("She said \"hello\" to {% include \"components/hero\" %}.")
            == "<p>She said \"hello\" to {% include \"components/hero\" %}.</p>")
    }
}
