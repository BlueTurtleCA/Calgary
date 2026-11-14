//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// CSSMinifier.swift
//

/// Minifies CSS: removes comments and collapses whitespace, while leaving
/// the contents of strings untouched.
///
/// Whitespace is collapsed to a single space and dropped around the
/// punctuation where it is never significant (`{`, `}`, `:`, `;`, `,`), so
/// `body   {   color:   red;   }` becomes `body{color:red;}`. Spaces
/// between other tokens (for example, `font: 12px arial`) are kept, since
/// removing them would merge two tokens into one.
enum CSSMinifier {
    /// The characters that may abut whitespace freely.
    private static let freeAbutting: Set<Character> = ["{", "}", ":", ";", ","]

    /// Returns a minified copy of `css`.
    static func minify(_ css: String) -> String {
        let characters = Array(css)
        var result = ""
        var pendingSpace = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "/" && index + 1 < characters.count && characters[index + 1] == "*" {
                // A block comment: skip it, keeping a space in its place so
                // tokens on either side do not run together.
                if let end = endIndex(of: ["*", "/"], from: index + 2, in: characters) {
                    pendingSpace = true
                    index = end + 2
                } else {
                    // The comment is never closed: skip the rest.
                    index = characters.count
                }
                continue
            }

            if character == "\"" || character == "'" {
                // A string: copy it through to the matching quote,
                // unchanged.
                var end = index + 1
                while end < characters.count && characters[end] != character {
                    end += 1
                }
                flushSpace(&result, pendingSpace: &pendingSpace, before: character)
                result.append(contentsOf: characters[index...min(end, characters.count - 1)])
                index = min(end, characters.count - 1) + 1
                continue
            }

            if character.isWhitespace {
                pendingSpace = true
                index += 1
                continue
            }

            flushSpace(&result, pendingSpace: &pendingSpace, before: character)
            result.append(character)
            index += 1
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Appends the pending space, if any, before `character` — unless the
    /// space would sit next to punctuation it is not needed around.
    private static func flushSpace(_ result: inout String, pendingSpace: inout Bool, before character: Character) {
        guard pendingSpace else { return }
        pendingSpace = false
        if freeAbutting.contains(character) { return }
        if let last = result.last, freeAbutting.contains(last) { return }
        result.append(" ")
    }

    /// The index of the first occurrence of the two-character sequence
    /// `sequence` at or after `start`, or `nil` if it does not occur.
    private static func endIndex(of sequence: [Character], from start: Int, in characters: [Character]) -> Int? {
        var search = start
        while search + sequence.count <= characters.count {
            var found = true
            for offset in sequence.indices {
                if characters[search + offset] != sequence[offset] {
                    found = false
                    break
                }
            }
            if found {
                return search
            }
            search += 1
        }
        return nil
    }
}
