import Foundation
import Testing
@testable import Calgary

@Suite("Variables")
struct VariablesTests {
    @Test("Looks up a top-level variable")
    func looksUpTopLevelVariable() {
        let variables = Variables(["title": .string("Blue Turtle")])
        #expect(variables["title"] == .string("Blue Turtle"))
    }

    @Test("Looks up variables with dot notation")
    func looksUpWithDotNotation() {
        let variables = Variables([
            "site": .map(["name": .string("Blue Turtle Canada")]),
        ])
        #expect(variables["site.name"] == .string("Blue Turtle Canada"))
    }

    @Test("Returns nil for a missing variable")
    func returnsNilForMissingVariable() {
        let variables = Variables(["title": .string("Blue Turtle")])
        #expect(variables["subtitle"] == nil)
    }

    @Test("Returns nil when an intermediate value is not a map")
    func returnsNilWhenIntermediateIsNotAMap() {
        let variables = Variables(["title": .string("Blue Turtle")])
        #expect(variables["title.first"] == nil)
    }

    @Test("Merging layers the other context on top")
    func mergingLayersOtherOnTop() {
        let base = Variables([
            "title": .string("Base"),
            "site": .map(["name": .string("Base Site")]),
        ])
        let overlay = Variables(["title": .string("Overlay")])

        let merged = base.merged(with: overlay)

        #expect(merged["title"] == .string("Overlay"))
        #expect(merged["site.name"] == .string("Base Site"))
    }

    @Test("Scalar values interpolate as plain text")
    func scalarValuesInterpolateAsPlainText() {
        #expect(Variable.string("hi").stringValue == "hi")
        #expect(Variable.integer(42).stringValue == "42")
        #expect(Variable.number(1.5).stringValue == "1.5")
        #expect(Variable.boolean(true).stringValue == "true")
    }
}
