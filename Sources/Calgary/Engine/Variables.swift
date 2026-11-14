//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// Variables.swift
//

import Foundation

/// A single template variable value.
///
/// Values come from a page's frontmatter (YAML), from the site's
/// `templateVariables`, or from built-ins, and are looked up with dot
/// notation when a template is rendered.
public indirect enum Variable: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case list([Variable])
    case map([String: Variable])

    /// The value as plain text, for interpolation into a template.
    public var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return value.description
        case .number(let value):
            return value.description
        case .boolean(let value):
            return value.description
        case .list(let items):
            return items.map(\.stringValue).joined(separator: ", ")
        case .map(let map):
            return map
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.stringValue)" }
                .joined(separator: ", ")
        }
    }

    /// Whether the value counts as true in a conditional: a non-empty
    /// string, a non-zero number, a true boolean, or a non-empty list or
    /// map.
    var isTruthy: Bool {
        switch self {
        case .string(let value):
            return !value.isEmpty
        case .integer(let value):
            return value != 0
        case .number(let value):
            return value != 0
        case .boolean(let value):
            return value
        case .list(let items):
            return !items.isEmpty
        case .map(let map):
            return !map.isEmpty
        }
    }

    /// Whether two values are equal for a conditional comparison: exact
    /// equality, or equal string form when both are scalars (so `3 == "3"`
    /// holds).
    func isEqualTo(_ other: Variable) -> Bool {
        if self == other {
            return true
        }
        switch (self, other) {
        case (.list, _), (_, .list), (.map, _), (_, .map):
            return false
        default:
            return stringValue == other.stringValue
        }
    }
}

/// A context of template variables, supporting dot-notation lookup.
struct Variables: Equatable, Sendable {
    let values: [String: Variable]

    init(_ values: [String: Variable] = [:]) {
        self.values = values
    }

    /// Looks up a variable by (possibly dot-notation) name.
    ///
    /// "title" looks up the top-level "title"; "site.name" walks into the
    /// "site" map and looks up "name".
    subscript(name: String) -> Variable? {
        var current = Variable.map(values)
        for part in name.split(separator: ".") {
            guard case .map(let map) = current, let next = map[String(part)] else {
                return nil
            }
            current = next
        }
        return current
    }

    /// Returns a context with `other`'s top-level values layered on top of
    /// this one.
    func merged(with other: Variables) -> Variables {
        var result = values
        for (key, value) in other.values {
            result[key] = value
        }
        return Variables(result)
    }
}
