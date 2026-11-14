//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// Glob.swift
//

import Foundation

/// Glob matching for file paths, shared by the steps that filter files
/// (for example, rendering pages and minifying output).
///
/// A glob supports `*` (any characters except `/`), `**/` (any number of
/// directories, including none), `**` (any characters), and `{a,b}`
/// (alternation).
enum Glob {
    /// Whether `path` matches `glob`.
    static func matches(_ glob: String, path: String) -> Bool {
        guard let pattern = pattern(from: glob) else { return false }
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$") else { return false }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    /// Converts a glob into a regular-expression pattern, or `nil` if the
    /// glob is malformed (an unterminated `{`).
    static func pattern(from glob: String) -> String? {
        var pattern = ""
        var index = glob.startIndex
        while index < glob.endIndex {
            let character = glob[index]
            if character == "*" {
                if glob[index...].hasPrefix("**/") {
                    pattern += "(?:[^/]+/)*"
                    index = glob.index(index, offsetBy: 3)
                    continue
                } else if glob[index...].hasPrefix("**") {
                    pattern += ".*"
                    index = glob.index(index, offsetBy: 2)
                    continue
                } else {
                    pattern += "[^/]*"
                }
            } else if character == "{" {
                guard let close = glob[index...].firstIndex(of: "}") else { return nil }
                let alternatives = glob[glob.index(after: index)..<close]
                    .split(separator: ",")
                    .compactMap { Self.pattern(from: String($0)) }
                guard !alternatives.isEmpty else { return nil }
                pattern += "(?:" + alternatives.joined(separator: "|") + ")"
                index = glob.index(after: close)
                continue
            } else if ".\\+?()[]{}^$|".contains(character) {
                pattern += "\\" + String(character)
            } else {
                pattern += String(character)
            }
            index = glob.index(after: index)
        }
        return pattern
    }
}
