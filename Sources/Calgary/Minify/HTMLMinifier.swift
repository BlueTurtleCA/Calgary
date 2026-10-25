/// Minifies HTML: removes comments and collapses whitespace, while leaving
/// the contents of raw elements (`<script>`, `<style>`, `<textarea>`,
/// `<pre>`, and `<code>`) untouched, where whitespace is significant.
///
/// The minifier is a small scanner rather than a set of regular expressions:
/// it tracks whether it is inside a raw element and respects quoted
/// attribute values, so constructs like `<a title="a > b">` and
/// `<pre>  spaced   out  </pre>` survive intact.
enum HTMLMinifier {
    /// The tag names whose contents are passed through unchanged.
    private static let rawElements: Set<String> = ["script", "style", "textarea", "pre", "code"]

    /// Returns a minified copy of `html`.
    static func minify(_ html: String) -> String {
        let characters = Array(html)
        var result = ""
        var pendingSpace = false
        var lastWasTag = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "<", isTagStart(at: index, in: characters) {
                if let commentEnd = commentEnd(at: index, in: characters) {
                    // A comment becomes a single space, so text on either
                    // side of it does not run together.
                    pendingSpace = true
                    index = commentEnd + 1
                    continue
                }
                if let tagEnd = tagEnd(at: index, in: characters) {
                    let tag = String(characters[index...tagEnd])
                    if let rawName = rawElementName(of: tag) {
                        // Pass the raw element's contents through
                        // unchanged, up to and including its closing tag.
                        if let closeEnd = rawElementEnd(after: tagEnd, named: rawName, in: characters) {
                            appendTag(tag, to: &result, pendingSpace: &pendingSpace, lastWasTag: &lastWasTag)
                            result.append(contentsOf: characters[(tagEnd + 1)...closeEnd])
                            lastWasTag = true
                            index = closeEnd + 1
                            continue
                        }
                        // The raw element is never closed: keep the rest of
                        // the document as-is.
                        result.append(contentsOf: characters[index...])
                        break
                    }
                    appendTag(tag, to: &result, pendingSpace: &pendingSpace, lastWasTag: &lastWasTag)
                    index = tagEnd + 1
                    continue
                }
            }

            if character.isWhitespace {
                pendingSpace = true
            } else {
                flushSpace(&result, pendingSpace: &pendingSpace, lastWasTag: &lastWasTag)
                result.append(character)
                lastWasTag = false
            }
            index += 1
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Scanning

    /// Whether the `<` at `index` can start a tag or comment, the way a
    /// browser would treat it: a `<` followed by a letter, `/`, `!`, or `?`.
    /// A `<` followed by anything else (for example, `a < b`) is text.
    private static func isTagStart(at index: Int, in characters: [Character]) -> Bool {
        guard index + 1 < characters.count else { return false }
        let next = characters[index + 1]
        return next.isLetter || next == "/" || next == "!" || next == "?"
    }

    /// The index of the `>` that closes the comment starting at `index`
    /// (where the text begins with `<!--`), or `nil` if there is no comment
    /// there or it is not closed.
    private static func commentEnd(at index: Int, in characters: [Character]) -> Int? {
        guard characters[index...].starts(with: ["<", "!", "-", "-"]) else { return nil }
        var search = index + 4
        while search + 2 < characters.count {
            if characters[search] == "-" && characters[search + 1] == "-" && characters[search + 2] == ">" {
                return search + 2
            }
            search += 1
        }
        return nil
    }

    /// The index of the `>` that closes the tag starting at `index`
    /// (where `characters[index] == "<"`), or `nil` if the tag is not
    /// closed. Quoted attribute values are respected, so a `>` inside
    /// `title="a > b"` does not end the tag.
    private static func tagEnd(at index: Int, in characters: [Character]) -> Int? {
        var quote: Character?
        var search = index + 1
        while search < characters.count {
            let character = characters[search]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return search
            }
            search += 1
        }
        return nil
    }

    /// The raw element's name if `tag` is an opening tag of one (for
    /// example, `script` for `<script type="text/javascript">`), or `nil`
    /// for closing tags, self-closing tags, and tags of other elements.
    private static func rawElementName(of tag: String) -> String? {
        guard !tag.hasPrefix("</") else { return nil }
        guard !tag.hasSuffix("/>") else { return nil }
        var name = ""
        var index = tag.index(after: tag.startIndex) // skip the "<"
        while index < tag.endIndex, tag[index].isLetter {
            name.append(tag[index])
            index = tag.index(after: index)
        }
        let lowercased = name.lowercased()
        guard rawElements.contains(lowercased) else { return nil }
        return lowercased
    }

    /// The index of the `>` that closes the raw element named `name`,
    /// searching from `start` (the index just after the opening tag's
    /// `>`), or `nil` if the element is not closed. The match is
    /// case-insensitive, the way browsers treat tag names.
    private static func rawElementEnd(after start: Int, named name: String, in characters: [Character]) -> Int? {
        let closePrefix = Array("</" + name)
        var search = start
        while search + closePrefix.count <= characters.count {
            if starts(with: closePrefix, at: search, in: characters) {
                let afterName = search + closePrefix.count
                guard afterName < characters.count else { return nil }
                let next = characters[afterName]
                if next == ">" {
                    return afterName
                }
                if next.isWhitespace {
                    var close = afterName + 1
                    while close < characters.count {
                        if characters[close] == ">" { return close }
                        close += 1
                    }
                    return nil
                }
            }
            search += 1
        }
        return nil
    }

    /// Whether `characters` begins with `prefix` at `index`, comparing
    /// case-insensitively.
    private static func starts(with prefix: [Character], at index: Int, in characters: [Character]) -> Bool {
        guard index + prefix.count <= characters.count else { return false }
        for offset in prefix.indices {
            if characters[index + offset].lowercased() != prefix[offset].lowercased() {
                return false
            }
        }
        return true
    }

    // MARK: Output

    /// Appends a tag to `result`, flushing any pending space first — unless
    /// the previous output was also a tag, in which case the space between
    /// the two tags is insignificant and is dropped.
    private static func appendTag(
        _ tag: String,
        to result: inout String,
        pendingSpace: inout Bool,
        lastWasTag: inout Bool
    ) {
        if pendingSpace {
            if lastWasTag {
                pendingSpace = false
            } else {
                result.append(" ")
                pendingSpace = false
            }
        }
        result.append(tag)
        lastWasTag = true
    }

    /// Appends the pending space, if any, to `result`.
    private static func flushSpace(_ result: inout String, pendingSpace: inout Bool, lastWasTag: inout Bool) {
        if pendingSpace {
            result.append(" ")
            pendingSpace = false
            lastWasTag = false
        }
    }
}
