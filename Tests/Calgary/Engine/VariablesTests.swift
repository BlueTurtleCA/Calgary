//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// VariablesTests.swift
//

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

    @Test("Reports truthiness for each value kind")
    func reportsTruthyForEachValueKind() {
        #expect(Variable.string("hi").isTruthy)
        #expect(!Variable.string("").isTruthy)
        #expect(Variable.integer(5).isTruthy)
        #expect(!Variable.integer(0).isTruthy)
        #expect(Variable.number(1.5).isTruthy)
        #expect(!Variable.number(0).isTruthy)
        #expect(Variable.boolean(true).isTruthy)
        #expect(!Variable.boolean(false).isTruthy)
        #expect(Variable.list([.string("a")]).isTruthy)
        #expect(!Variable.list([]).isTruthy)
        #expect(Variable.map(["a": .string("x")]).isTruthy)
        #expect(!Variable.map([:]).isTruthy)
    }

    @Test("Compares scalar values across types by string form")
    func comparesScalarValuesAcrossTypes() {
        #expect(Variable.integer(3).isEqualTo(.string("3")))
        #expect(Variable.string("3").isEqualTo(.integer(3)))
        #expect(!Variable.integer(3).isEqualTo(.string("4")))
        #expect(Variable.string("hi").isEqualTo(.string("hi")))
        #expect(!Variable.string("hi").isEqualTo(.string("there")))
        #expect(!Variable.list([.string("3")]).isEqualTo(.string("3")))
    }
}
