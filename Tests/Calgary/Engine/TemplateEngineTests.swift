import Foundation
import Testing
@testable import Calgary

@Suite("TemplateEngine")
struct TemplateEngineTests {
    /// Creates an engine and resolver over a file system seeded with the
    /// given components (path → content).
    private func makeEnvironment(
        fileSystem: InMemoryFileSystem,
        components: [String: String] = [:]
    ) throws -> (engine: TemplateEngine, resolver: ComponentResolver) {
        for (path, content) in components {
            try writeFile(content, at: path, relativeTo: virtualRoot, in: fileSystem)
        }
        let resolver = ComponentResolver(root: virtualRoot, fileSystem: fileSystem)
        return (TemplateEngine(), resolver)
    }

    @Test("Interpolates a variable")
    func interpolatesVariable() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "Hi, {{ name }}!",
            variables: Variables(["name": .string("Turtle")]),
            resolver: resolver
        )

        #expect(result == "Hi, Turtle!")
    }

    @Test("Interpolates a dot-notation variable")
    func interpolatesDotNotationVariable() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{{ site.name }}",
            variables: Variables(["site": .map(["name": .string("Blue Turtle Canada")])]),
            resolver: resolver
        )

        #expect(result == "Blue Turtle Canada")
    }

    @Test("Throws when a variable is missing")
    func throwsWhenVariableIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.missingVariable("title")) {
            try engine.render("{{ title }}", variables: Variables(), resolver: resolver)
        }
    }

    @Test("Resolves an include")
    func resolvesInclude() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "<section>hero</section>"]
        )

        let result = try engine.render(
            "before{% include \"components/hero\" %}after",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result == "before<section>hero</section>after")
    }

    @Test("Interpolates variables inside a component")
    func interpolatesVariablesInsideComponent() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/header.html": "<header>{{ site.name }}</header>"]
        )

        let result = try engine.render(
            "{% include \"components/header\" %}",
            variables: Variables(["site": .map(["name": .string("Blue Turtle Canada")])]),
            resolver: resolver
        )

        #expect(result == "<header>Blue Turtle Canada</header>")
    }

    @Test("Resolves nested includes")
    func resolvesNestedIncludes() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: [
                "components/outer.html": "outer[{% include \"components/inner\" %}]",
                "components/inner.html": "inner",
            ]
        )

        let result = try engine.render(
            "{% include \"components/outer\" %}",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result == "outer[inner]")
    }

    @Test("Detects cyclic includes")
    func detectsCyclicIncludes() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: [
                "components/a.html": "{% include \"components/b\" %}",
                "components/b.html": "{% include \"components/a\" %}",
            ]
        )

        #expect(throws: TemplateError.self) {
            try engine.render("{% include \"components/a\" %}", variables: Variables(), resolver: resolver)
        }
    }

    @Test("Throws when a component is not found")
    func throwsWhenComponentIsNotFound() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.componentNotFound("components/missing")) {
            try engine.render("{% include \"components/missing\" %}", variables: Variables(), resolver: resolver)
        }
    }

    @Test("Renders a markdown component to HTML")
    func rendersMarkdownComponentToHTML() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.md": "## {{ title }}\n\nA calm corner of the web."]
        )

        let result = try engine.render(
            "{% include \"components/hero\" %}",
            variables: Variables(["title": .string("Welcome")]),
            resolver: resolver
        )

        #expect(result.contains("<h2>Welcome</h2>") == true)
        #expect(result.contains("<p>A calm corner of the web.</p>") == true)
    }

    @Test("Resolves includes inside a markdown component")
    func resolvesIncludesInsideMarkdownComponent() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: [
                "components/outer.md": "An outer component.\n\n{% include \"components/inner\" %}",
                "components/inner.md": "The **inner** component.",
            ]
        )

        let result = try engine.render(
            "{% include \"components/outer\" %}",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result.contains("<p>An outer component.</p>") == true)
        #expect(result.contains("<strong>inner</strong>") == true)
    }

    @Test("Leaves text without tags unchanged")
    func leavesTextWithoutTagsUnchanged() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "No tags here, just text with { single } braces.",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result == "No tags here, just text with { single } braces.")
    }

    @Test("Tolerates extra whitespace inside tags")
    func toleratesExtraWhitespaceInsideTags() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "hero"]
        )

        let result = try engine.render(
            "{{  name  }}{%  include \"components/hero\"  %}",
            variables: Variables(["name": .string("Turtle")]),
            resolver: resolver
        )

        #expect(result == "Turtlehero")
    }
}
