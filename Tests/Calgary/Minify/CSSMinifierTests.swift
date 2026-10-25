import Foundation
import Testing
@testable import Calgary

@Suite("CSSMinifier")
struct CSSMinifierTests {
    @Test("Removes comments and collapses whitespace")
    func removesCommentsAndCollapsesWhitespace() {
        #expect(
            CSSMinifier.minify("/* note */\nbody   {   color:   red;   }") == "body{color:red;}"
        )
    }

    @Test("A comment between tokens becomes a space")
    func commentBetweenTokensBecomesSpace() {
        #expect(CSSMinifier.minify("a /* c */ b") == "a b")
    }

    @Test("A comment after '{' does not add a space")
    func commentAfterOpenBraceAddsNoSpace() {
        #expect(CSSMinifier.minify("a { /* c */ color: red }") == "a{color:red}")
    }

    @Test("Keeps a space between two identifiers")
    func keepsSpaceBetweenIdentifiers() {
        #expect(CSSMinifier.minify("font: 12px arial") == "font:12px arial")
    }

    @Test("Keeps the contents of strings unchanged")
    func keepsStringContents() {
        #expect(CSSMinifier.minify(".a { content: \"  {  \"; }") == ".a{content:\"  {  \";}")
    }

    @Test("Keeps a space around '/'")
    func keepsSpaceAroundSlash() {
        #expect(CSSMinifier.minify(".a { width: 100% / 2; }") == ".a{width:100% / 2;}")
    }

    @Test("Minifies a media query")
    func minifiesMediaQuery() {
        #expect(
            CSSMinifier.minify("@media (min-width: 400px) { .a { color: red; } }")
                == "@media (min-width:400px){.a{color:red;}}"
        )
    }

    @Test("Drops an unterminated comment and the rest of the file")
    func unterminatedCommentDropsTheRest() {
        #expect(CSSMinifier.minify("/* unclosed") == "")
    }

    @Test("Trims leading and trailing whitespace")
    func trimsLeadingAndTrailingWhitespace() {
        #expect(CSSMinifier.minify("  .a { color: red; }  ") == ".a{color:red;}")
    }
}
