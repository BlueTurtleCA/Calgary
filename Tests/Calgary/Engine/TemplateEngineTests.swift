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

    @Test("Passes arguments to an include")
    func passesArgumentsToInclude() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/header.html": "<header>{{ title }}</header>"]
        )

        let result = try engine.render(
            "{% include \"components/header\" title=\"Blue Turtle Canada\" %}",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result == "<header>Blue Turtle Canada</header>")
    }

    @Test("Arguments shadow outer variables of the same name")
    func argumentsShadowOuterVariables() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/header.html": "<header>{{ title }}</header>"]
        )

        let result = try engine.render(
            "{% include \"components/header\" title=\"Inner\" %}",
            variables: Variables(["title": .string("Outer")]),
            resolver: resolver
        )

        #expect(result == "<header>Inner</header>")
    }

    @Test("Outer variables remain visible in a component with arguments")
    func outerVariablesRemainVisibleInComponentWithArguments() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/header.html": "<header>{{ site.name }} / {{ title }}</header>"]
        )

        let result = try engine.render(
            "{% include \"components/header\" title=\"Home\" %}",
            variables: Variables(["site": .map(["name": .string("Blue Turtle Canada")])]),
            resolver: resolver
        )

        #expect(result == "<header>Blue Turtle Canada / Home</header>")
    }

    @Test("Arguments are visible in nested includes")
    func argumentsAreVisibleInNestedIncludes() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: [
                "components/outer.html": "outer[{% include \"components/inner\" %}]",
                "components/inner.html": "{{ title }}",
            ]
        )

        let result = try engine.render(
            "{% include \"components/outer\" title=\"Nested\" %}",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result == "outer[Nested]")
    }

    @Test("Passes arguments to a markdown component")
    func passesArgumentsToMarkdownComponent() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.md": "## {{ title }}"]
        )

        let result = try engine.render(
            "{% include \"components/hero\" title=\"Welcome\" %}",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result.contains("<h2>Welcome</h2>") == true)
    }

    @Test("Tolerates whitespace around argument equals signs")
    func toleratesWhitespaceAroundArgumentEqualsSigns() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "{{ title }}"]
        )

        let result = try engine.render(
            "{%  include \"components/hero\"  title = \"Turtle\"  %}",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result == "Turtle")
    }

    @Test("Leaves an include with a malformed argument untouched")
    func leavesIncludeWithMalformedArgumentUntouched() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "hero"]
        )

        let result = try engine.render(
            "{% include \"components/hero\" title=Turtle %}",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result == "{% include \"components/hero\" title=Turtle %}")
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

    // MARK: Variable arguments

    @Test("Passes a variable as an include argument")
    func passesVariableAsIncludeArgument() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/header.html": "<header>{{ title }}</header>"]
        )

        let result = try engine.render(
            "{% include \"components/header\" title={{ title }} %}",
            variables: Variables(["title": .string("Blue Turtle Canada")]),
            resolver: resolver
        )

        #expect(result == "<header>Blue Turtle Canada</header>")
    }

    @Test("Passes a dot-notation variable as an include argument")
    func passesDotNotationVariableAsIncludeArgument() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "<p>{{ tagline }}</p>"]
        )

        let result = try engine.render(
            "{% include \"components/hero\" tagline={{ strings.hero.tagline }} %}",
            variables: Variables([
                "strings": .map(["hero": .map(["tagline": .string("A calm corner of the web.")])]),
            ]),
            resolver: resolver
        )

        #expect(result == "<p>A calm corner of the web.</p>")
    }

    @Test("Keeps the type of a variable argument")
    func keepsTypeOfVariableArgument() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "{% if count == 3 %}three{% else %}other{% endif %}"]
        )

        let result = try engine.render(
            "{% include \"components/hero\" count={{ count }} %}",
            variables: Variables(["count": .integer(3)]),
            resolver: resolver
        )

        #expect(result == "three")
    }

    @Test("Mixes literal and variable arguments in one include")
    func mixesLiteralAndVariableArguments() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "{{ a }}-{{ b }}"]
        )

        let result = try engine.render(
            "{% include \"components/hero\" a=\"literal\" b={{ b }} %}",
            variables: Variables(["b": .string("variable")]),
            resolver: resolver
        )

        #expect(result == "literal-variable")
    }

    @Test("Throws when a variable argument is missing")
    func throwsWhenVariableArgumentIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "{{ title }}"]
        )

        #expect(throws: TemplateError.missingVariable("missing")) {
            try engine.render(
                "{% include \"components/hero\" title={{ missing }} %}",
                variables: Variables(),
                resolver: resolver
            )
        }
    }

    // MARK: Conditionals

    @Test("Renders the then branch when a variable is truthy")
    func rendersThenBranchWhenTruthy() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% if title %}present{% endif %}",
            variables: Variables(["title": .string("Blue Turtle")]),
            resolver: resolver
        )

        #expect(result == "present")
    }

    @Test("Renders nothing when a variable is falsy and there is no else")
    func rendersNothingWhenFalsyWithoutElse() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% if flag %}present{% endif %}",
            variables: Variables(["flag": .boolean(false)]),
            resolver: resolver
        )

        #expect(result == "")
    }

    @Test("Treats a missing variable as false in a truthiness check")
    func treatsMissingVariableAsFalseInTruthinessCheck() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% if missing %}present{% endif %}",
            variables: Variables(),
            resolver: resolver
        )

        #expect(result == "")
    }

    @Test("Renders the else branch when the condition is false")
    func rendersElseBranchWhenFalse() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% if flag %}yes{% else %}no{% endif %}",
            variables: Variables(["flag": .boolean(false)]),
            resolver: resolver
        )

        #expect(result == "no")
    }

    @Test("Compares a variable with a string literal")
    func comparesVariableWithStringLiteral() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)
        let template = "{% if page.locale == \"en\" %}English{% else %}Other{% endif %}"

        let english = try engine.render(
            template,
            variables: Variables(["page": .map(["locale": .string("en")])]),
            resolver: resolver
        )
        let french = try engine.render(
            template,
            variables: Variables(["page": .map(["locale": .string("fr-fr")])]),
            resolver: resolver
        )

        #expect(english == "English")
        #expect(french == "Other")
    }

    @Test("Compares a variable with a number")
    func comparesVariableWithNumber() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% if count == 3 %}three{% else %}other{% endif %}",
            variables: Variables(["count": .integer(3)]),
            resolver: resolver
        )

        #expect(result == "three")
    }

    @Test("Compares two variables")
    func comparesTwoVariables() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% if a == b %}equal{% else %}different{% endif %}",
            variables: Variables(["a": .string("x"), "b": .string("x")]),
            resolver: resolver
        )

        #expect(result == "equal")
    }

    @Test("Supports the not-equal operator")
    func supportsNotEqualOperator() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% if page.locale != \"en\" %}other{% endif %}",
            variables: Variables(["page": .map(["locale": .string("fr-fr")])]),
            resolver: resolver
        )

        #expect(result == "other")
    }

    @Test("Evaluates nested conditionals")
    func evaluatesNestedConditionals() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)
        let template = "{% if a %}A{% if b %}B{% endif %}{% endif %}"

        let both = try engine.render(
            template,
            variables: Variables(["a": .boolean(true), "b": .boolean(true)]),
            resolver: resolver
        )
        let outerOnly = try engine.render(
            template,
            variables: Variables(["a": .boolean(true), "b": .boolean(false)]),
            resolver: resolver
        )

        #expect(both == "AB")
        #expect(outerOnly == "A")
    }

    @Test("Resolves includes inside a conditional branch")
    func resolvesIncludesInsideConditionalBranch() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/hero.html": "hero"]
        )

        let result = try engine.render(
            "{% if title %}{% include \"components/hero\" %}{% endif %}",
            variables: Variables(["title": .string("Welcome")]),
            resolver: resolver
        )

        #expect(result == "hero")
    }

    @Test("Evaluates conditionals inside a component")
    func evaluatesConditionalsInsideComponent() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/greeting.html": "{% if title %}Hi {{ title }}{% else %}Hello{% endif %}"]
        )

        let result = try engine.render(
            "{% include \"components/greeting\" title={{ name }} %}",
            variables: Variables(["name": .string("Turtle")]),
            resolver: resolver
        )

        #expect(result == "Hi Turtle")
    }

    @Test("Tolerates whitespace inside conditional tags")
    func toleratesWhitespaceInsideConditionalTags() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{%  if  title  %}yes{%  else  %}no{%  endif  %}",
            variables: Variables(["title": .string("Blue Turtle")]),
            resolver: resolver
        )

        #expect(result == "yes")
    }

    @Test("Throws when an if has no endif")
    func throwsWhenIfHasNoEndif() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.self) {
            try engine.render(
                "{% if title %}present",
                variables: Variables(["title": .string("Blue Turtle")]),
                resolver: resolver
            )
        }
    }

    @Test("Throws on a stray else")
    func throwsOnStrayElse() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.unexpectedConditionalTag("else")) {
            try engine.render("{% else %}", variables: Variables(), resolver: resolver)
        }
    }

    @Test("Throws on a stray endif")
    func throwsOnStrayEndif() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.unexpectedConditionalTag("endif")) {
            try engine.render("{% endif %}", variables: Variables(), resolver: resolver)
        }
    }

    @Test("Throws on an empty condition")
    func throwsOnEmptyCondition() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.self) {
            try engine.render("{% if %}yes{% endif %}", variables: Variables(), resolver: resolver)
        }
    }

    @Test("Throws when a comparison references a missing variable")
    func throwsWhenComparisonReferencesMissingVariable() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.missingVariable("missing")) {
            try engine.render(
                "{% if missing == \"x\" %}yes{% endif %}",
                variables: Variables(),
                resolver: resolver
            )
        }
    }
}
