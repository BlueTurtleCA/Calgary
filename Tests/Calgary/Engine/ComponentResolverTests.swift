import Foundation
import Testing
@testable import Calgary

@Suite("ComponentResolver")
struct ComponentResolverTests {
    private func makeResolver(fileSystem: InMemoryFileSystem) -> ComponentResolver {
        ComponentResolver(root: virtualRoot, fileSystem: fileSystem)
    }

    @Test("Resolves a component with an .html extension")
    func resolvesHTMLComponent() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<section>hero</section>", at: "components/hero.html", relativeTo: virtualRoot, in: fileSystem)

        let resolved = try makeResolver(fileSystem: fileSystem).resolve("components/hero", stack: [])

        #expect(resolved.content == "<section>hero</section>")
        #expect(resolved.resolvedPath == virtualRoot.appendingPathComponent("components/hero.html").path)
        #expect(resolved.isMarkdown == false)
    }

    @Test("Resolves a markdown component")
    func resolvesMarkdownComponent() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("## Hero", at: "components/hero.md", relativeTo: virtualRoot, in: fileSystem)

        let resolved = try makeResolver(fileSystem: fileSystem).resolve("components/hero", stack: [])

        #expect(resolved.content == "## Hero")
        #expect(resolved.resolvedPath == virtualRoot.appendingPathComponent("components/hero.md").path)
        #expect(resolved.isMarkdown == true)
    }

    @Test("Prefers the .md variant when both exist")
    func prefersMarkdownVariant() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("md", at: "components/hero.md", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("html", at: "components/hero.html", relativeTo: virtualRoot, in: fileSystem)

        let resolved = try makeResolver(fileSystem: fileSystem).resolve("components/hero", stack: [])

        #expect(resolved.content == "md")
        #expect(resolved.isMarkdown == true)
    }

    @Test("Resolves a path that already has a .md extension")
    func resolvesExplicitMarkdownPath() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("hero", at: "components/hero.md", relativeTo: virtualRoot, in: fileSystem)

        let resolved = try makeResolver(fileSystem: fileSystem).resolve("components/hero.md", stack: [])

        #expect(resolved.content == "hero")
        #expect(resolved.isMarkdown == true)
    }

    @Test("Resolves a component without an extension")
    func resolvesExtensionlessComponent() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("raw", at: "components/hero", relativeTo: virtualRoot, in: fileSystem)

        let resolved = try makeResolver(fileSystem: fileSystem).resolve("components/hero", stack: [])

        #expect(resolved.content == "raw")
    }

    @Test("Prefers the .html variant when both exist")
    func prefersHTMLVariant() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("html", at: "components/hero.html", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("raw", at: "components/hero", relativeTo: virtualRoot, in: fileSystem)

        let resolved = try makeResolver(fileSystem: fileSystem).resolve("components/hero", stack: [])

        #expect(resolved.content == "html")
    }

    @Test("Resolves a path that already has an .html extension")
    func resolvesExplicitHTMLPath() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("hero", at: "components/hero.html", relativeTo: virtualRoot, in: fileSystem)

        let resolved = try makeResolver(fileSystem: fileSystem).resolve("components/hero.html", stack: [])

        #expect(resolved.content == "hero")
    }

    @Test("Throws when the component does not exist")
    func throwsWhenComponentIsMissing() throws {
        let fileSystem = InMemoryFileSystem()

        #expect(throws: TemplateError.componentNotFound("components/missing")) {
            try makeResolver(fileSystem: fileSystem).resolve("components/missing", stack: [])
        }
    }

    @Test("Detects a cycle through the resolution stack")
    func detectsCycleThroughStack() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("a", at: "components/a.html", relativeTo: virtualRoot, in: fileSystem)
        let resolver = makeResolver(fileSystem: fileSystem)
        let aPath = virtualRoot.appendingPathComponent("components/a.html").path

        #expect(throws: TemplateError.self) {
            try resolver.resolve("components/a", stack: [aPath])
        }
    }
}
