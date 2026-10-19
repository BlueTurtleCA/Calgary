import Foundation
import Yams

/// A page's parsed frontmatter and body.
struct Page: Equatable {
    /// The name of the template to render the page with.
    let template: String
    /// The page's date, if declared in the frontmatter.
    let date: String?
    /// Variables declared in the frontmatter.
    let variables: Variables
    /// The page's markdown body.
    let body: String
}

/// Errors that can occur while parsing a page's frontmatter.
enum FrontmatterError: Error, Equatable, CustomStringConvertible {
    /// The page does not start with a `---` line.
    case missingOpeningDelimiter
    /// The frontmatter is never closed with a `---` line.
    case missingClosingDelimiter
    /// The frontmatter is not valid YAML.
    case invalidYAML(String)
    /// The frontmatter does not declare a `template`.
    case missingTemplate

    var description: String {
        switch self {
        case .missingOpeningDelimiter:
            return "Page is missing its frontmatter (it must start with '---')"
        case .missingClosingDelimiter:
            return "Frontmatter is missing its closing '---' line"
        case .invalidYAML(let detail):
            return "Frontmatter is not valid YAML: \(detail)"
        case .missingTemplate:
            return "Frontmatter is missing a 'template'"
        }
    }
}

/// Splits and parses a page's YAML frontmatter.
enum Frontmatter {
    /// Parses `text` into a page.
    ///
    /// The text must start with a `---` line, followed by YAML, followed by a
    /// closing `---` line. The YAML must declare a `template`; it may declare
    /// a `date` and a `variables` map. Everything after the closing `---` is
    /// the page's body.
    static func parse(_ text: String) throws -> Page {
        let (yaml, body) = try split(text)
        guard let node = try Yams.compose(yaml: yaml) else {
            throw FrontmatterError.missingTemplate
        }
        guard case .mapping(let mapping) = node else {
            throw FrontmatterError.invalidYAML("the frontmatter must be a YAML mapping")
        }

        var template: String?
        var date: String?
        var variables: [String: Variable] = [:]

        for (key, value) in mapping {
            guard case .scalar(let keyScalar) = key else { continue }
            switch keyScalar.string {
            case "template":
                guard case .scalar(let valueScalar) = value else {
                    throw FrontmatterError.invalidYAML("'template' must be a string")
                }
                template = valueScalar.string
            case "date":
                if case .scalar(let valueScalar) = value {
                    date = valueScalar.string
                }
            case "variables":
                let variable = try variable(from: value)
                if case .map(let map) = variable {
                    variables = map
                }
            default:
                break
            }
        }

        guard let template else {
            throw FrontmatterError.missingTemplate
        }
        return Page(template: template, date: date, variables: Variables(variables), body: body)
    }

    /// Splits `text` into its YAML frontmatter and body.
    static func split(_ text: String) throws -> (yaml: String, body: String) {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            throw FrontmatterError.missingOpeningDelimiter
        }
        var closingIndex: Int?
        for (index, line) in lines.enumerated() where index > 0 {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = index
                break
            }
        }
        guard let closing = closingIndex else {
            throw FrontmatterError.missingClosingDelimiter
        }
        let yaml = lines[1..<closing].joined(separator: "\n")
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return (yaml, body)
    }

    /// Converts a YAML node into a variable value.
    static func variable(from node: Node) throws -> Variable {
        switch node {
        case .scalar(let scalar):
            let value = scalar.string
            if value == "true" { return .boolean(true) }
            if value == "false" { return .boolean(false) }
            if let integer = Int(value) { return .integer(integer) }
            if let number = Double(value) { return .number(number) }
            return .string(value)
        case .sequence(let sequence):
            return .list(try sequence.map { try variable(from: $0) })
        case .mapping(let mapping):
            var result: [String: Variable] = [:]
            for (key, value) in mapping {
                guard case .scalar(let keyScalar) = key else { continue }
                result[keyScalar.string] = try variable(from: value)
            }
            return .map(result)
        case .alias:
            throw FrontmatterError.invalidYAML("aliases are not supported")
        }
    }
}
