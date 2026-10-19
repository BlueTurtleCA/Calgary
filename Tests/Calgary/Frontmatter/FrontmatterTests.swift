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

    @Test("Throws when the template is missing")
    func throwsWhenTemplateIsMissing() {
        #expect(throws: FrontmatterError.missingTemplate) {
            try Frontmatter.parse("---\nvariables:\n  title: Hi\n---\nBody")
        }
    }

    @Test("Throws when the frontmatter is not a YAML mapping")
    func throwsWhenFrontmatterIsNotAMapping() {
        #expect(throws: FrontmatterError.self) {
            try Frontmatter.parse("---\n- just\n- a\n- list\n---\nBody")
        }
    }
}
