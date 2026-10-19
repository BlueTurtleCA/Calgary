import Foundation

/// Errors that can occur while rendering a template.
enum TemplateError: Error, Equatable, CustomStringConvertible {
    /// A `{{ variable }}` in the template has no value in the context.
    case missingVariable(String)
    /// An `{% include %}` path could not be resolved to a component.
    case componentNotFound(String)
    /// An include chain refers to a component that is already being rendered.
    case cyclicInclude([String])
    /// A page's template could not be found in the templates directory.
    case templateNotFound(String)

    var description: String {
        switch self {
        case .missingVariable(let name):
            return "Missing variable: \(name)"
        case .componentNotFound(let path):
            return "Component not found: \(path)"
        case .cyclicInclude(let chain):
            return "Cyclic include detected: \(chain.joined(separator: " → "))"
        case .templateNotFound(let name):
            return "Template not found: \(name)"
        }
    }
}

/// Renders templates: resolves `{% include "path" %}` tags and interpolates
/// `{{ variable }}` tags (dot notation supported).
///
/// Includes are resolved first — each component is rendered recursively with
/// the same variables, so components can use variables and include other
/// components. Markdown components are rendered to HTML before they pass
/// through the engine. The remaining text is then interpolated.
struct TemplateEngine: Sendable {
    /// The renderer used to convert markdown components to HTML.
    let markdownRenderer: MarkdownRenderer

    init(markdownRenderer: MarkdownRenderer = MarkdownRenderer()) {
        self.markdownRenderer = markdownRenderer
    }

    /// Renders `text` with `variables`, resolving includes via `resolver`.
    ///
    /// - Parameter stack: The resolved component file paths currently being
    ///   rendered, used for cycle detection. Leave empty when starting a render.
    func render(
        _ text: String,
        variables: Variables,
        resolver: ComponentResolver,
        stack: [String] = []
    ) throws -> String {
        let withIncludes = try resolveIncludes(in: text, variables: variables, resolver: resolver, stack: stack)
        return try interpolate(withIncludes, variables: variables)
    }

    // MARK: Includes

    private static let includePattern = "\\{%\\s*include\\s+\"([^\"]+)\"\\s*%\\}"

    private func resolveIncludes(
        in text: String,
        variables: Variables,
        resolver: ComponentResolver,
        stack: [String]
    ) throws -> String {
        var result = ""
        var searchStart = text.startIndex
        let regex = try NSRegularExpression(pattern: Self.includePattern)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard
                let matchRange = Range(match.range, in: text),
                let pathRange = Range(match.range(at: 1), in: text)
            else { continue }
            result += text[searchStart..<matchRange.lowerBound]
            let path = String(text[pathRange])
            let resolved = try resolver.resolve(path, stack: stack)
            // Markdown components render to HTML first, then pass through
            // the engine, so they can nest and use variables.
            let content = resolved.isMarkdown ? markdownRenderer.render(resolved.content) : resolved.content
            let rendered = try render(
                content,
                variables: variables,
                resolver: resolver,
                stack: stack + [resolved.resolvedPath]
            )
            result += rendered
            searchStart = matchRange.upperBound
        }
        result += text[searchStart...]
        return result
    }

    // MARK: Interpolation

    private static let variablePattern = "\\{\\{\\s*([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*)\\s*\\}\\}"

    private func interpolate(_ text: String, variables: Variables) throws -> String {
        var result = ""
        var searchStart = text.startIndex
        let regex = try NSRegularExpression(pattern: Self.variablePattern)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard
                let matchRange = Range(match.range, in: text),
                let nameRange = Range(match.range(at: 1), in: text)
            else { continue }
            result += text[searchStart..<matchRange.lowerBound]
            let name = String(text[nameRange])
            guard let variable = variables[name] else {
                throw TemplateError.missingVariable(name)
            }
            result += variable.stringValue
            searchStart = matchRange.upperBound
        }
        result += text[searchStart...]
        return result
    }
}
