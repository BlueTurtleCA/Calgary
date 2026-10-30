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

    // MARK: String placeholders

    @Test("Expands placeholders in a strings value")
    func expandsPlaceholdersInStringsValue() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{{ strings.footer.copyright }}",
            variables: Variables([
                "site": .map(["year": .integer(2026)]),
                "strings": .map([
                    "footer": .map([
                        "copyright": .string("Copyright {{ site.year }} My Company. All rights reserved."),
                    ]),
                ]),
            ]),
            resolver: resolver
        )

        #expect(result == "Copyright 2026 My Company. All rights reserved.")
    }

    @Test("Leaves a strings value without placeholders unchanged")
    func leavesStringsValueWithoutPlaceholdersUnchanged() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{{ strings.nav.home }}",
            variables: Variables([
                "strings": .map(["nav": .map(["home": .string("Home")])]),
            ]),
            resolver: resolver
        )

        #expect(result == "Home")
    }

    @Test("Leaves a non-strings value containing placeholders untouched")
    func leavesNonStringsValueContainingPlaceholdersUntouched() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{{ note }}",
            variables: Variables(["note": .string("Use {{ title }} here")]),
            resolver: resolver
        )

        #expect(result == "Use {{ title }} here")
    }

    @Test("Expands a string that references another string")
    func expandsStringReferencingAnotherString() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{{ strings.footer.copyright }}",
            variables: Variables([
                "site": .map(["year": .integer(2026)]),
                "strings": .map([
                    "company": .map(["name": .string("My Company")]),
                    "footer": .map([
                        "copyright": .string("Copyright {{ site.year }} {{ strings.company.name }}."),
                    ]),
                ]),
            ]),
            resolver: resolver
        )

        #expect(result == "Copyright 2026 My Company.")
    }

    @Test("Throws when a string placeholder references a missing variable")
    func throwsWhenStringPlaceholderReferencesMissingVariable() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.missingVariable("site.year")) {
            try engine.render(
                "{{ strings.footer.copyright }}",
                variables: Variables([
                    "strings": .map([
                        "footer": .map(["copyright": .string("Copyright {{ site.year }}.")]),
                    ]),
                ]),
                resolver: resolver
            )
        }
    }

    @Test("Detects a string that refers to itself")
    func detectsSelfReferencingString() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.cyclicString(["strings.a", "strings.a"])) {
            try engine.render(
                "{{ strings.a }}",
                variables: Variables([
                    "strings": .map(["a": .string("{{ strings.a }}")]),
                ]),
                resolver: resolver
            )
        }
    }

    @Test("Detects strings that refer to each other")
    func detectsMutuallyReferencingStrings() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.self) {
            try engine.render(
                "{{ strings.a }}",
                variables: Variables([
                    "strings": .map([
                        "a": .string("{{ strings.b }}"),
                        "b": .string("{{ strings.a }}"),
                    ]),
                ]),
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

    // MARK: Loops

    @Test("Renders a loop over a list")
    func rendersLoopOverList() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% for item in items %}<li>{{ item }}</li>{% endfor %}",
            variables: Variables(["items": .list([.string("a"), .string("b"), .string("c")])]),
            resolver: resolver
        )

        #expect(result == "<li>a</li><li>b</li><li>c</li>")
    }

    @Test("Renders the else branch when the list is empty")
    func rendersElseBranchWhenListIsEmpty() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% for item in items %}<li>{{ item }}</li>{% else %}<p>none</p>{% endfor %}",
            variables: Variables(["items": .list([])]),
            resolver: resolver
        )

        #expect(result == "<p>none</p>")
    }

    @Test("Renders nothing when the list is empty and there is no else")
    func rendersNothingWhenListIsEmptyWithoutElse() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% for item in items %}<li>{{ item }}</li>{% endfor %}",
            variables: Variables(["items": .list([])]),
            resolver: resolver
        )

        #expect(result == "")
    }

    @Test("Iterates over a list of maps with dot notation")
    func iteratesOverListOfMaps() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% for page in pages %}<a href=\"{{ page.url }}\">{{ page.title }}</a>{% endfor %}",
            variables: Variables([
                "pages": .list([
                    .map(["title": .string("Home"), "url": .string("/index.html")]),
                    .map(["title": .string("About"), "url": .string("/about.html")]),
                ]),
            ]),
            resolver: resolver
        )

        #expect(result == "<a href=\"/index.html\">Home</a><a href=\"/about.html\">About</a>")
    }

    @Test("Iterates over a dot-notation collection")
    func iteratesOverDotNotationCollection() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% for item in site.items %}{{ item }}{% endfor %}",
            variables: Variables(["site": .map(["items": .list([.string("a"), .string("b")])])]),
            resolver: resolver
        )

        #expect(result == "ab")
    }

    @Test("Supports conditionals inside a loop")
    func supportsConditionalsInsideLoop() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% for item in items %}{% if item == \"b\" %}<b>{{ item }}</b>{% else %}{{ item }}{% endif %}{% endfor %}",
            variables: Variables(["items": .list([.string("a"), .string("b"), .string("c")])]),
            resolver: resolver
        )

        #expect(result == "a<b>b</b>c")
    }

    @Test("Supports includes inside a loop")
    func supportsIncludesInsideLoop() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(
            fileSystem: fileSystem,
            components: ["components/card.html": "<card>{{ title }}</card>"]
        )

        let result = try engine.render(
            "{% for item in items %}{% include \"components/card\" title={{ item }} %}{% endfor %}",
            variables: Variables(["items": .list([.string("a"), .string("b")])]),
            resolver: resolver
        )

        #expect(result == "<card>a</card><card>b</card>")
    }

    @Test("Supports nested loops")
    func supportsNestedLoops() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        let result = try engine.render(
            "{% for row in rows %}{% for col in row %}{{ col }}{% endfor %}|{% endfor %}",
            variables: Variables([
                "rows": .list([
                    .list([.string("a"), .string("b")]),
                    .list([.string("c")]),
                ]),
            ]),
            resolver: resolver
        )

        #expect(result == "ab|c|")
    }

    @Test("A loop can be wrapped by a conditional")
    func loopWrappedByConditional() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)
        let template = "{% if show %}{% for item in items %}{{ item }}{% endfor %}{% endif %}"

        let shown = try engine.render(
            template,
            variables: Variables(["show": .boolean(true), "items": .list([.string("a"), .string("b")])]),
            resolver: resolver
        )
        let hidden = try engine.render(
            template,
            variables: Variables(["show": .boolean(false), "items": .list([.string("a"), .string("b")])]),
            resolver: resolver
        )

        #expect(shown == "ab")
        #expect(hidden == "")
    }

    @Test("Throws when the loop collection is missing")
    func throwsWhenLoopCollectionIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.missingVariable("items")) {
            try engine.render(
                "{% for item in items %}{{ item }}{% endfor %}",
                variables: Variables(),
                resolver: resolver
            )
        }
    }

    @Test("Throws when the loop collection is not a list")
    func throwsWhenLoopCollectionIsNotAList() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.notAList("title")) {
            try engine.render(
                "{% for item in title %}{{ item }}{% endfor %}",
                variables: Variables(["title": .string("x")]),
                resolver: resolver
            )
        }
    }

    @Test("Throws when a for has no endfor")
    func throwsWhenForHasNoEndfor() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.self) {
            try engine.render(
                "{% for item in items %}{{ item }}",
                variables: Variables(["items": .list([.string("a")])]),
                resolver: resolver
            )
        }
    }

    @Test("Throws on a stray endfor")
    func throwsOnStrayEndfor() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.unexpectedLoopTag("endfor")) {
            try engine.render("{% endfor %}", variables: Variables(), resolver: resolver)
        }
    }

    @Test("Throws on an invalid for clause")
    func throwsOnInvalidForClause() throws {
        let fileSystem = InMemoryFileSystem()
        let (engine, resolver) = try makeEnvironment(fileSystem: fileSystem)

        #expect(throws: TemplateError.self) {
            try engine.render(
                "{% for items %}{{ item }}{% endfor %}",
                variables: Variables(["items": .list([.string("a")])]),
                resolver: resolver
            )
        }
    }
}
