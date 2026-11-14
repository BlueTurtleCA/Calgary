//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// StringTableTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("StringTable")
struct StringTableTests {
    /// Seeds a file system with English and French string files, then loads
    /// and returns the table.
    private func makeTable(fileSystem: InMemoryFileSystem) throws -> StringTable {
        try writeFile(
            """
            nav:
              home: Home
              about: About
            footer:
              builtWith: Built with Calgary.
            """,
            at: "strings/en.yaml",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        try writeFile(
            """
            nav:
              home: Accueil
            """,
            at: "strings/fr-fr.yaml",
            relativeTo: virtualRoot,
            in: fileSystem
        )
        var table = StringTable(defaultLocale: "en", fileSystem: fileSystem)
        try table.loadYAMLFiles(in: virtualRoot.appendingPathComponent("strings"))
        return table
    }

    /// A string catalog with English and French values. `nav.about` has no
    /// French translation, and the last entry uses plural variations, which
    /// are not supported.
    private let catalogJSON = """
    {
      "sourceLanguage" : "en",
      "strings" : {
        "nav.home" : {
          "localizations" : {
            "en" : { "stringUnit" : { "state" : "translated", "value" : "Home" } },
            "fr-FR" : { "stringUnit" : { "state" : "translated", "value" : "Accueil" } }
          }
        },
        "nav.about" : {
          "localizations" : {
            "en" : { "stringUnit" : { "state" : "translated", "value" : "About" } }
          }
        },
        "items" : {
          "localizations" : {
            "en" : {
              "variations" : {
                "plural" : {
                  "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld item" } },
                  "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld items" } }
                }
              }
            }
          }
        }
      },
      "version" : "1.0"
    }
    """

    private func makeCatalogTable(fileSystem: InMemoryFileSystem) throws -> StringTable {
        try writeFile(catalogJSON, at: "Localizable.xcstrings", relativeTo: virtualRoot, in: fileSystem)
        var table = StringTable(defaultLocale: "en", fileSystem: fileSystem)
        try table.loadCatalog(at: virtualRoot.appendingPathComponent("Localizable.xcstrings"))
        return table
    }

    @Test("Locale values win over the default locale")
    func localeValuesWinOverDefault() throws {
        let fileSystem = InMemoryFileSystem()
        let table = try makeTable(fileSystem: fileSystem)

        #expect(table.variables(for: "fr-fr")["strings.nav.home"] == .string("Accueil"))
    }

    @Test("Keys missing in the locale fall back to the default locale")
    func missingKeysFallBackToDefault() throws {
        let fileSystem = InMemoryFileSystem()
        let table = try makeTable(fileSystem: fileSystem)

        let variables = table.variables(for: "fr-fr")
        #expect(variables["strings.nav.about"] == .string("About"))
        #expect(variables["strings.footer.builtWith"] == .string("Built with Calgary."))
    }

    @Test("The default locale resolves its own strings")
    func defaultLocaleResolvesOwnStrings() throws {
        let fileSystem = InMemoryFileSystem()
        let table = try makeTable(fileSystem: fileSystem)

        #expect(table.variables(for: "en")["strings.nav.home"] == .string("Home"))
    }

    @Test("A locale without a string file uses the default locale")
    func localeWithoutFileUsesDefault() throws {
        let fileSystem = InMemoryFileSystem()
        let table = try makeTable(fileSystem: fileSystem)

        #expect(table.variables(for: "de")["strings.nav.home"] == .string("Home"))
    }

    @Test("Ignores files that are not YAML string files")
    func ignoresNonStringFiles() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("nav:\n  home: Home\n", at: "strings/en.yaml", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("not a string file", at: "strings/notes.txt", relativeTo: virtualRoot, in: fileSystem)

        var table = StringTable(defaultLocale: "en", fileSystem: fileSystem)
        try table.loadYAMLFiles(in: virtualRoot.appendingPathComponent("strings"))

        #expect(table.variables(for: "en")["strings.nav.home"] == .string("Home"))
    }

    @Test("Throws when a string file is not a mapping")
    func throwsWhenFileIsNotAMapping() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("- just\n- a list\n", at: "strings/en.yaml", relativeTo: virtualRoot, in: fileSystem)

        var table = StringTable(defaultLocale: "en", fileSystem: fileSystem)

        #expect(throws: StringTableError.notAMapping(virtualRoot.appendingPathComponent("strings/en.yaml").path)) {
            try table.loadYAMLFiles(in: virtualRoot.appendingPathComponent("strings"))
        }
    }

    @Test("Loads catalog values, matching locale IDs case-insensitively")
    func loadsCatalogValuesCaseInsensitively() throws {
        let fileSystem = InMemoryFileSystem()
        let table = try makeCatalogTable(fileSystem: fileSystem)

        #expect(table.variables(for: "en")["strings.nav.home"] == .string("Home"))
        #expect(table.variables(for: "fr-fr")["strings.nav.home"] == .string("Accueil"))
    }

    @Test("Catalog keys fall back to the default locale")
    func catalogKeysFallBackToDefault() throws {
        let fileSystem = InMemoryFileSystem()
        let table = try makeCatalogTable(fileSystem: fileSystem)

        #expect(table.variables(for: "fr-fr")["strings.nav.about"] == .string("About"))
    }

    @Test("Skips catalog entries without a simple value")
    func skipsEntriesWithoutAValue() throws {
        let fileSystem = InMemoryFileSystem()
        let table = try makeCatalogTable(fileSystem: fileSystem)

        #expect(table.variables(for: "en")["strings.items"] == nil)
        #expect(table.variables(for: "en")["strings.nav.home"] == .string("Home"))
    }

    @Test("Throws when the catalog is not valid JSON")
    func throwsWhenCatalogIsNotValidJSON() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("not json", at: "Localizable.xcstrings", relativeTo: virtualRoot, in: fileSystem)

        var table = StringTable(defaultLocale: "en", fileSystem: fileSystem)

        #expect(throws: StringTableError.invalidCatalog(virtualRoot.appendingPathComponent("Localizable.xcstrings").path)) {
            try table.loadCatalog(at: virtualRoot.appendingPathComponent("Localizable.xcstrings"))
        }
    }

    @Test("Throws when the catalog has no strings entry")
    func throwsWhenCatalogHasNoStrings() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("{\"sourceLanguage\" : \"en\"}", at: "Localizable.xcstrings", relativeTo: virtualRoot, in: fileSystem)

        var table = StringTable(defaultLocale: "en", fileSystem: fileSystem)

        #expect(throws: StringTableError.invalidCatalog(virtualRoot.appendingPathComponent("Localizable.xcstrings").path)) {
            try table.loadCatalog(at: virtualRoot.appendingPathComponent("Localizable.xcstrings"))
        }
    }
}
