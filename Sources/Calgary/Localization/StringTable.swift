//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// StringTable.swift
//

import Foundation
import Yams

/// Errors that can occur while loading string files.
enum StringTableError: Error, Equatable, CustomStringConvertible {
    /// A string file is not a YAML mapping.
    case notAMapping(String)

    /// A string catalog is not valid JSON or is missing its `strings` entry.
    case invalidCatalog(String)

    var description: String {
        switch self {
        case .notAMapping(let path):
            return "String file is not a YAML mapping: \(path)"
        case .invalidCatalog(let path):
            return "String catalog is not valid JSON with a 'strings' entry: \(path)"
        }
    }
}

/// Loads the site's strings and serves them as template variables.
///
/// Strings come from one of two sources:
///
/// - A directory of per-locale YAML files, one per locale, named
///   `<locale>.yaml` (or `.yml`).
/// - An Xcode string catalog (`.xcstrings`): a single JSON file holding
///   every locale. Keys are flat, and a dot in a key becomes a nesting
///   level, so `nav.home` resolves as `{{ strings.nav.home }}`. Locale IDs
///   are matched case-insensitively, so Xcode's `fr-FR` satisfies the
///   site's `fr-fr`.
///
/// When a page is rendered, the active locale's strings are deep-merged over
/// the default locale's strings and exposed under the `strings` variable, so
/// any key missing in the locale falls back to the default locale.
struct StringTable: Sendable {
    private let defaultLocale: String
    private let fileSystem: any FileSystem

    /// The loaded strings for each locale: locale → top-level mapping.
    private var tables: [String: [String: Variable]] = [:]

    init(defaultLocale: String, fileSystem: any FileSystem) {
        self.defaultLocale = defaultLocale
        self.fileSystem = fileSystem
    }

    /// Loads every `<locale>.yaml`/`.yml` file in the directory.
    mutating func loadYAMLFiles(in directory: URL) throws {
        for entry in try fileSystem.contentsOfDirectory(at: directory) {
            let name = entry.lastPathComponent
            guard name.hasSuffix(".yaml") || name.hasSuffix(".yml") else { continue }
            let locale = entry.deletingPathExtension().lastPathComponent
            let data = try fileSystem.read(contentsOf: entry)
            let text = String(data: data, encoding: .utf8) ?? ""
            tables[locale] = try Self.parseYAML(text, at: entry.path)
        }
    }

    /// Loads an Xcode string catalog (`.xcstrings`) file.
    ///
    /// Only simple string values are read; entries with plural or device
    /// variations are skipped.
    mutating func loadCatalog(at url: URL) throws {
        let data = try fileSystem.read(contentsOf: url)
        guard
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let strings = object["strings"] as? [String: Any]
        else {
            throw StringTableError.invalidCatalog(url.path)
        }
        for (key, entry) in strings {
            guard
                let entryObject = entry as? [String: Any],
                let localizations = entryObject["localizations"] as? [String: Any]
            else { continue }
            for (locale, localization) in localizations {
                guard
                    let localizationObject = localization as? [String: Any],
                    let stringUnit = localizationObject["stringUnit"] as? [String: Any],
                    let value = stringUnit["value"] as? String
                else { continue }
                insert(value, forKey: key, locale: locale.lowercased())
            }
        }
    }

    /// Returns a variable context exposing the active locale's strings,
    /// deep-merged over the default locale's, under the `strings` key.
    func variables(for locale: String) -> Variables {
        let base = tables[defaultLocale] ?? [:]
        let override = tables[locale] ?? [:]
        return Variables(["strings": .map(Self.deepMerge(base: base, over: override))])
    }

    private mutating func insert(_ value: String, forKey key: String, locale: String) {
        let components = key.split(separator: ".").map(String.init)
        tables[locale] = Self.nestedMerge(into: tables[locale] ?? [:], components: components, value: .string(value))
    }

    /// Inserts `value` into `base` at the dot-separated path `components`,
    /// creating intermediate mappings as needed.
    private static func nestedMerge(
        into base: [String: Variable],
        components: [String],
        value: Variable
    ) -> [String: Variable] {
        guard let head = components.first else { return base }
        var result = base
        if components.count == 1 {
            result[head] = value
        } else {
            var child: [String: Variable] = [:]
            if case .map(let existing) = result[head] {
                child = existing
            }
            result[head] = .map(nestedMerge(into: child, components: Array(components.dropFirst()), value: value))
        }
        return result
    }

    private static func parseYAML(_ text: String, at path: String) throws -> [String: Variable] {
        guard let node = try Yams.compose(yaml: text) else { return [:] }
        guard case .mapping(let mapping) = node else {
            throw StringTableError.notAMapping(path)
        }
        var result: [String: Variable] = [:]
        for (key, value) in mapping {
            guard case .scalar(let keyScalar) = key else { continue }
            result[keyScalar.string] = try Frontmatter.variable(from: value)
        }
        return result
    }

    /// Merges two string mappings, with `override` winning. Nested mappings
    /// are merged key by key, so a key absent from `override` keeps its value
    /// from `base`.
    static func deepMerge(base: [String: Variable], over override: [String: Variable]) -> [String: Variable] {
        var result = base
        for (key, value) in override {
            if case .map(let overrideMap) = value, case .map(let baseMap) = result[key] {
                result[key] = .map(deepMerge(base: baseMap, over: overrideMap))
            } else {
                result[key] = value
            }
        }
        return result
    }
}
