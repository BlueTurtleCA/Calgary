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
    /// An `{% if %}` has no matching `{% endif %}`.
    case unclosedConditional(String)
    /// An `{% else %}` or `{% endif %}` appears without a matching `{% if %}`.
    case unexpectedConditionalTag(String)
    /// An `{% if %}` condition could not be parsed.
    case invalidCondition(String)

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
        case .unclosedConditional(let condition):
            return "Unclosed conditional: {% if \(condition) %} has no {% endif %}"
        case .unexpectedConditionalTag(let tag):
            return "Unexpected {% \(tag) %}: no matching {% if %}"
        case .invalidCondition(let condition):
            return "Invalid condition: \(condition)"
        }
    }
}

/// Renders templates: evaluates `{% if %}` conditionals, resolves
/// `{% include "path" %}` tags, and interpolates `{{ variable }}` tags
/// (dot notation supported).
///
/// Conditionals are processed first, then includes — each component is
/// rendered recursively with the current variables, plus any arguments
/// passed to the include (literal `key="value"` or variable
/// `key={{ variable }}`) layered on top, so components can use variables
/// and include other components. Markdown components are rendered to HTML
/// before they pass through the engine. The remaining text is then
/// interpolated.
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
        let withConditionals = try processConditionals(in: text, variables: variables)
        let withIncludes = try resolveIncludes(in: withConditionals, variables: variables, resolver: resolver, stack: stack)
        return try interpolate(withIncludes, variables: variables)
    }

    // MARK: Conditionals

    /// Matches an `{% if %}` tag; group 1 is the condition (possibly empty).
    private static let ifPattern = "\\{%\\s*if\\b\\s*(.*?)\\s*%\\}"

    /// Matches any conditional tag; group 1 is the tag name (`if`, `else`,
    /// or `endif`), group 2 the condition (for `if`, possibly empty).
    private static let conditionalTagPattern = "\\{%\\s*(if|else|endif)\\b\\s*(.*?)\\s*%\\}"

    /// Evaluates `{% if %}` conditionals, keeping the branch whose condition
    /// holds. Runs before includes and interpolation so a chosen branch can
    /// contain either.
    private func processConditionals(in text: String, variables: Variables) throws -> String {
        guard let ifMatch = try Self.firstMatch(of: Self.ifPattern, in: text) else {
            try guardAgainstStrayTags(in: text)
            return text
        }
        // The text before the first if cannot contain another if; reject
        // stray tags in it.
        try guardAgainstStrayTags(in: String(text[..<ifMatch.range.lowerBound]))

        // Find the matching {% else %} / {% endif %}, tracking nested ifs.
        var depth = 1
        var elseRange: Range<String.Index>?
        var endRange: Range<String.Index>?
        let tagRegex = try NSRegularExpression(pattern: Self.conditionalTagPattern)
        for match in tagRegex.matches(in: text, range: NSRange(ifMatch.range.upperBound..., in: text)) {
            guard
                let range = Range(match.range, in: text),
                let nameRange = Range(match.range(at: 1), in: text)
            else { continue }
            let name = String(text[nameRange])
            if name == "if" {
                depth += 1
            } else if name == "else", depth == 1 {
                elseRange = range
            } else if name == "endif" {
                depth -= 1
                if depth == 0 {
                    endRange = range
                    break
                }
            }
        }
        guard let endRange else {
            throw TemplateError.unclosedConditional(Self.conditionText(of: ifMatch, in: text))
        }

        let condition = Self.conditionText(of: ifMatch, in: text)
        let isTrue = try evaluate(condition, variables: variables)
        let branchEnd = elseRange?.lowerBound ?? endRange.lowerBound
        let thenBranch = String(text[ifMatch.range.upperBound..<branchEnd])
        let elseBranch = elseRange.map { String(text[$0.upperBound..<endRange.lowerBound]) } ?? ""
        let kept = isTrue ? thenBranch : elseBranch
        let keptRendered = try processConditionals(in: kept, variables: variables)
        let suffixRendered = try processConditionals(in: String(text[endRange.upperBound...]), variables: variables)
        return String(text[..<ifMatch.range.lowerBound]) + keptRendered + suffixRendered
    }

    /// Throws when `text` contains an `{% else %}` or `{% endif %}` that has
    /// no matching `{% if %}`.
    private func guardAgainstStrayTags(in text: String) throws {
        let regex = try NSRegularExpression(pattern: Self.conditionalTagPattern)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange])
            if name == "else" || name == "endif" {
                throw TemplateError.unexpectedConditionalTag(name)
            }
        }
    }

    /// Evaluates a condition against `variables`.
    ///
    /// A condition is either a bare variable (a truthiness check; a missing
    /// variable is simply false) or a `==`/`!=` comparison of two operands.
    /// An operand is a quoted string, a number, or a variable reference. A
    /// missing variable in a comparison is an error, since the author
    /// expects the value to exist.
    private func evaluate(_ condition: String, variables: Variables) throws -> Bool {
        let trimmed = condition.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw TemplateError.invalidCondition(condition)
        }
        if let (left, op, right) = Self.splitComparison(trimmed) {
            let leftValue = try Self.value(of: left, in: condition, variables: variables)
            let rightValue = try Self.value(of: right, in: condition, variables: variables)
            let equal = leftValue.isEqualTo(rightValue)
            return op == "==" ? equal : !equal
        }
        guard Self.isVariableName(trimmed) else {
            throw TemplateError.invalidCondition(condition)
        }
        return variables[trimmed]?.isTruthy ?? false
    }

    /// Splits a condition on `==` or `!=`, if present.
    private static func splitComparison(_ condition: String) -> (left: String, op: String, right: String)? {
        for op in ["==", "!="] {
            if let range = condition.range(of: op) {
                return (
                    String(condition[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    op,
                    String(condition[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                )
            }
        }
        return nil
    }

    /// Resolves a comparison operand: a quoted string, a number, or a
    /// variable reference.
    private static func value(of operand: String, in condition: String, variables: Variables) throws -> Variable {
        let trimmed = operand.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw TemplateError.invalidCondition(condition)
        }
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return .string(String(trimmed.dropFirst().dropLast()))
        }
        if let integer = Int(trimmed) {
            return .integer(integer)
        }
        if let number = Double(trimmed) {
            return .number(number)
        }
        guard isVariableName(trimmed) else {
            throw TemplateError.invalidCondition(condition)
        }
        guard let variable = variables[trimmed] else {
            throw TemplateError.missingVariable(trimmed)
        }
        return variable
    }

    private static let variableNamePattern = "^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)*$"

    private static func isVariableName(_ text: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", Self.variableNamePattern).evaluate(with: text)
    }

    // MARK: Includes

    /// Matches an include tag: the component path in quotes, followed by an
    /// optional block of arguments. An argument is `key="value"` (a literal)
    /// or `key={{ variable }}` (a variable reference).
    private static let includePattern =
        "\\{%\\s*include\\s+\"([^\"]+)\"((?:\\s+[A-Za-z0-9_]+\\s*=\\s*(?:\"[^\"]*\"|\\{\\{\\s*[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*\\s*\\}\\}))*)\\s*%\\}"

    /// Matches a single argument inside an include tag; group 2 is the
    /// literal value and group 3 the variable name (the absent one did not
    /// participate in the match).
    private static let argumentPattern =
        "([A-Za-z0-9_]+)\\s*=\\s*(?:\"([^\"]*)\"|\\{\\{\\s*([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*)\\s*\\}\\})"

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
            // Arguments passed to the include layer on top of the current
            // variables, scoped to the component and its nested includes.
            var scopedVariables = variables
            if let argumentsRange = Range(match.range(at: 2), in: text), !argumentsRange.isEmpty {
                let arguments = try Self.parseArguments(String(text[argumentsRange]), variables: variables)
                scopedVariables = variables.merged(with: Variables(arguments))
            }
            let resolved = try resolver.resolve(path, stack: stack)
            // Markdown components render to HTML first, then pass through
            // the engine, so they can nest and use variables.
            let content = resolved.isMarkdown ? markdownRenderer.render(resolved.content) : resolved.content
            let rendered = try render(
                content,
                variables: scopedVariables,
                resolver: resolver,
                stack: stack + [resolved.resolvedPath]
            )
            result += rendered
            searchStart = matchRange.upperBound
        }
        result += text[searchStart...]
        return result
    }

    /// Parses arguments from an include's argument block.
    ///
    /// A `key="value"` argument is a literal string; a `key={{ variable }}`
    /// argument is resolved against `variables` and keeps its type. A
    /// missing variable is an error. Duplicate keys: the last one wins.
    private static func parseArguments(_ text: String, variables: Variables) throws -> [String: Variable] {
        var arguments: [String: Variable] = [:]
        let regex = try NSRegularExpression(pattern: Self.argumentPattern)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange])
            if let literalRange = Range(match.range(at: 2), in: text) {
                arguments[key] = .string(String(text[literalRange]))
            } else if let nameRange = Range(match.range(at: 3), in: text) {
                let name = String(text[nameRange])
                guard let variable = variables[name] else {
                    throw TemplateError.missingVariable(name)
                }
                arguments[key] = variable
            }
        }
        return arguments
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

    // MARK: Regex helpers

    /// A regular-expression match: the full match range and, when the
    /// pattern has a first capture group, its range.
    private struct Match {
        let range: Range<String.Index>
        let group1: Range<String.Index>?
    }

    /// Finds the first match of `pattern` in `text`.
    private static func firstMatch(of pattern: String, in text: String) throws -> Match? {
        let regex = try NSRegularExpression(pattern: pattern)
        guard
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range, in: text)
        else { return nil }
        return Match(range: range, group1: Range(match.range(at: 1), in: text))
    }

    /// The condition captured by an `{% if %}` match.
    private static func conditionText(of match: Match, in text: String) -> String {
        guard let group1 = match.group1 else { return "" }
        return String(text[group1])
    }
}
