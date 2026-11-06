import Foundation
import Testing
@testable import Calgary

@Suite("Frontmatter")
struct FrontmatterTests {
    @Test("Parses the template, variables, and body")
    func parsesTemplateVariablesAndBody() throws {
        let page = try Frontmatter.parse(
            """
            ---
            template: home
            variables:
              title: Blue Turtle Canada
            ---

            Hi, welcome to {{ title }}!
            """
        )

        #expect(page.template == "home")
        #expect(page.variables["title"] == .string("Blue Turtle Canada"))
        #expect(page.body.contains("Hi, welcome to {{ title }}!") == true)
    }

    @Test("Parses nested variables")
    func parsesNestedVariables() throws {
        let page = try Frontmatter.parse(
            """
            ---
            template: home
            variables:
              hero:
                heading: Welcome
            ---
            """
        )

        #expect(page.variables["hero.heading"] == .string("Welcome"))
    }

    @Test("Parses scalar variable types")
    func parsesScalarVariableTypes() throws {
        let page = try Frontmatter.parse(
            """
            ---
            template: home
            variables:
              count: 3
              ratio: 1.5
              draft: true
            ---
            """
        )

        #expect(page.variables["count"] == .integer(3))
        #expect(page.variables["ratio"] == .number(1.5))
        #expect(page.variables["draft"] == .boolean(true))
    }

    @Test("Parses the date")
    func parsesDate() throws {
        let page = try Frontmatter.parse(
            """
            ---
            template: home
            date: 2026-01-01
            ---
            """
        )

        #expect(page.date == "2026-01-01")
    }

    @Test("Allows a page without variables")
    func allowsPageWithoutVariables() throws {
        let page = try Frontmatter.parse(
            """
            ---
            template: home
            ---
            Body only.
            """
        )

        #expect(page.template == "home")
        #expect(page.variables["title"] == nil)
        #expect(page.body == "Body only.")
    }

    @Test("Throws when the opening delimiter is missing")
    func throwsWhenOpeningDelimiterIsMissing() {
        #expect(throws: FrontmatterError.missingOpeningDelimiter) {
            try Frontmatter.parse("template: home\n---\nBody")
        }
    }

    @Test("Throws when the closing delimiter is missing")
    func throwsWhenClosingDelimiterIsMissing() {
        #expect(throws: FrontmatterError.missingClosingDelimiter) {
            try Frontmatter.parse("---\ntemplate: home\nBody")
        }
    }

    @Test("Allows a markdown page without a template")
    func allowsMarkdownPageWithoutTemplate() throws {
        // The render step enforces a template (or a collection's default);
        // the parser does not.
        let page = try Frontmatter.parse("---\nvariables:\n  title: Hi\n---\nBody")

        #expect(page.template == nil)
        #expect(page.variables["title"] == .string("Hi"))
    }

    @Test("Parses top-level keys as variables")
    func parsesTopLevelKeysAsVariables() throws {
        let page = try Frontmatter.parse(
            """
            ---
            template: home
            title: A Post
            description: A short description.
            image: /images/post.jpg
            ---
            """
        )

        #expect(page.variables["title"] == .string("A Post"))
        #expect(page.variables["description"] == .string("A short description."))
        #expect(page.variables["image"] == .string("/images/post.jpg"))
    }

    @Test("A top-level key wins over a same-named variables entry")
    func topLevelKeyWinsOverVariablesEntry() throws {
        let page = try Frontmatter.parse(
            """
            ---
            template: home
            title: Top level
            variables:
              title: Nested
            ---
            """
        )

        #expect(page.variables["title"] == .string("Top level"))
    }

    @Test("Throws when the frontmatter is not a YAML mapping")
    func throwsWhenFrontmatterIsNotAMapping() {
        #expect(throws: FrontmatterError.self) {
            try Frontmatter.parse("---\n- just\n- a\n- list\n---\nBody")
        }
    }

    @Test("Parses an HTML page without frontmatter")
    func parsesHTMLPageWithoutFrontmatter() throws {
        let page = try Frontmatter.parseHTML("<html><body>Hello</body></html>")

        #expect(page.template == nil)
        #expect(page.date == nil)
        #expect(page.variables["title"] == nil)
        #expect(page.body == "<html><body>Hello</body></html>")
    }

    @Test("Parses an HTML page's optional frontmatter")
    func parsesHTMLPageWithFrontmatter() throws {
        let page = try Frontmatter.parseHTML(
            """
            ---
            date: 2026-01-01
            variables:
              title: Hello
            ---
            <html><body>{{ title }}</body></html>
            """
        )

        #expect(page.template == nil)
        #expect(page.date == "2026-01-01")
        #expect(page.variables["title"] == .string("Hello"))
        #expect(page.body == "<html><body>{{ title }}</body></html>")
    }

    @Test("Throws when an HTML page declares a template")
    func throwsWhenHTMLPageDeclaresTemplate() {
        #expect(throws: FrontmatterError.templateNotAllowedInHTMLPage) {
            try Frontmatter.parseHTML("---\ntemplate: home\n---\n<html></html>")
        }
    }
}
