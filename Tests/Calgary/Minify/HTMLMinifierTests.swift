import Foundation
import Testing
@testable import Calgary

@Suite("HTMLMinifier")
struct HTMLMinifierTests {
    @Test("Removes comments between tags")
    func removesCommentsBetweenTags() {
        #expect(HTMLMinifier.minify("<div><!-- note --><p>Hi</p></div>") == "<div><p>Hi</p></div>")
    }

    @Test("A comment between text becomes a space")
    func commentBetweenTextBecomesSpace() {
        #expect(HTMLMinifier.minify("Hello<!-- c -->world") == "Hello world")
    }

    @Test("A comment at the start of the document is dropped")
    func commentAtStartIsDropped() {
        #expect(HTMLMinifier.minify("<!-- c --><div>Hi</div>") == "<div>Hi</div>")
    }

    @Test("Keeps the doctype")
    func keepsDoctype() {
        #expect(HTMLMinifier.minify("<!doctype html>\n<html>") == "<!doctype html><html>")
    }

    @Test("Collapses whitespace between tags")
    func collapsesWhitespaceBetweenTags() {
        #expect(
            HTMLMinifier.minify("<div>\n  <p>\n    Hi\n  </p>\n</div>") == "<div><p> Hi </p></div>"
        )
    }

    @Test("Keeps a single space between text and a tag")
    func keepsSpaceBetweenTextAndTag() {
        #expect(HTMLMinifier.minify("<div>Hello <b>world</b></div>") == "<div>Hello <b>world</b></div>")
    }

    @Test("Keeps a space between a text '>' and a tag")
    func keepsSpaceAfterTextGreaterThan() {
        #expect(HTMLMinifier.minify("<p>a > <b>b</b></p>") == "<p>a > <b>b</b></p>")
    }

    @Test("Treats a '<' that cannot start a tag as text")
    func bareLessThanIsText() {
        #expect(HTMLMinifier.minify("a < b") == "a < b")
    }

    @Test("Keeps an unclosed comment as text")
    func unclosedCommentIsText() {
        #expect(HTMLMinifier.minify("<!-- unclosed") == "<!-- unclosed")
    }

    @Test("Keeps the contents of <pre> unchanged")
    func keepsPreContents() {
        let html = "<pre>  a\n  b </pre>"
        #expect(HTMLMinifier.minify(html) == html)
    }

    @Test("Keeps the contents of <code> unchanged")
    func keepsCodeContents() {
        let html = "<p><code>x = 1  +  2</code></p>"
        #expect(HTMLMinifier.minify(html) == html)
    }

    @Test("Keeps the contents of <script> unchanged")
    func keepsScriptContents() {
        let html = "<script>\n  var a = 1; // comment\n</script>"
        #expect(HTMLMinifier.minify(html) == html)
    }

    @Test("Keeps the contents of <style> unchanged")
    func keepsStyleContents() {
        let html = "<style>\n  body { color: red; }\n</style>"
        #expect(HTMLMinifier.minify(html) == html)
    }

    @Test("Keeps the contents of <textarea> unchanged")
    func keepsTextareaContents() {
        let html = "<textarea>\n  line 1\n  line 2\n</textarea>"
        #expect(HTMLMinifier.minify(html) == html)
    }

    @Test("Matches raw element closing tags case-insensitively")
    func rawElementClosingTagIsCaseInsensitive() {
        let html = "<SCRIPT>var a = 1;</SCRIPT>"
        #expect(HTMLMinifier.minify(html) == html)
    }

    @Test("Keeps an unclosed raw element as-is")
    func unclosedRawElementIsKept() {
        let html = "<script>var a = 1;"
        #expect(HTMLMinifier.minify(html) == html)
    }

    @Test("Respects quoted attribute values containing '>'")
    func respectsQuotedAttributeValues() {
        let html = "<a title=\"a > b\">x</a>"
        #expect(HTMLMinifier.minify(html) == html)
    }

    @Test("Trims leading and trailing whitespace")
    func trimsLeadingAndTrailingWhitespace() {
        #expect(HTMLMinifier.minify("  <div>Hi</div>  ") == "<div>Hi</div>")
    }
}
