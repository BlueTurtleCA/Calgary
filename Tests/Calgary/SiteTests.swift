//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// SiteTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("Site")
struct SiteTests {
    @Test("Source and output default to 'content' and 'build'")
    func defaultSourceAndOutput() {
        let site = Site(name: "Test Site")

        #expect(site.source == "content")
        #expect(site.output == "build")
    }

    @Test("Root defaults to the current working directory")
    func rootDefaultsToCurrentWorkingDirectory() {
        let site = Site(name: "Test Site")
        let expectedRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        #expect(site.root == expectedRoot)
    }

    @Test("Relative paths resolve against the site's root")
    func relativePathsResolveAgainstRoot() {
        let site = Site(name: "Test Site", source: "content", output: "build", root: virtualRoot)

        #expect(site.sourceDirectory == virtualRoot.appendingPathComponent("content"))
        #expect(site.outputDirectory == virtualRoot.appendingPathComponent("build"))
    }

    @Test("Builder methods return the site so steps can be daisy-chained")
    func builderMethodsDaisyChain() {
        let site = Site(name: "Test Site", root: virtualRoot)
        let chained = site.copyAssets(from: "assets")

        #expect(chained === site)
        #expect(site.steps.count == 1)
        #expect(site.steps.first is CopyAssetsStep)
    }

    @Test("registerTemplates stores the templates directory")
    func registerTemplatesStoresDirectory() {
        let site = Site(name: "Test Site", root: virtualRoot)

        site.registerTemplates(in: "templates")

        #expect(site.templatesDirectory == "templates")
        #expect(site.steps.isEmpty)
    }

    @Test("registerComponents stores the components directory")
    func registerComponentsStoresDirectory() {
        let site = Site(name: "Test Site", root: virtualRoot)

        site.registerComponents(in: "components")

        #expect(site.componentsDirectory == "components")
        #expect(site.steps.isEmpty)
    }

    @Test("localize stores the localization configuration")
    func localizeStoresConfiguration() {
        let site = Site(name: "Test Site", root: virtualRoot)

        site.localize(defaultLocale: "en", locales: ["fr-fr"], strings: "strings")

        #expect(site.localization?.defaultLocale == "en")
        #expect(site.localization?.locales == ["en", "fr-fr"])
        #expect(site.localization?.stringsPath == "strings")
        #expect(site.steps.isEmpty)
    }

    @Test("renderPages adds a step that renders the default glob")
    func renderPagesAddsStep() {
        let site = Site(name: "Test Site", root: virtualRoot)

        site.renderPages()

        #expect(site.steps.count == 1)
        #expect(site.steps.first is RenderPagesStep)
        #expect(site.steps.first?.name == "Render pages matching '**/*.{md,html}'")
    }

    @Test("open adds a step that opens index.html by default")
    func openAddsStepWithDefaultPage() {
        let site = Site(name: "Test Site", root: virtualRoot)

        site.open()

        #expect(site.steps.count == 1)
        #expect(site.steps.first is OpenSiteStep)
        #expect(site.steps.first?.name == "Open 'index.html'")
    }

    @Test("build() creates the output directory")
    func buildCreatesOutputDirectory() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)

        try site.build()

        #expect(fileSystem.isDirectory(atPath: site.outputDirectory.path))
    }

    @Test("build() creates nested output directories")
    func buildCreatesNestedOutputDirectory() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", output: "dist/site", root: virtualRoot, fileSystem: fileSystem)

        try site.build()

        #expect(fileSystem.isDirectory(atPath: site.outputDirectory.path))
    }

    @Test("build() removes stale files from the output directory")
    func buildRemovesStaleFiles() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try writeFile("stale", at: "build/stale.txt", relativeTo: virtualRoot, in: fileSystem)

        try site.build()

        #expect(!fileSystem.fileExists(atPath: site.outputDirectory.appendingPathComponent("stale.txt").path))
    }

    @Test("build() runs steps in the order they were added")
    func stepsRunInOrder() throws {
        let fileSystem = InMemoryFileSystem()
        let recorder = StepRecorder()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
            .addStep(RecordingStep(label: "first", recorder: recorder))
            .addStep(RecordingStep(label: "second", recorder: recorder))

        try site.build()

        #expect(recorder.entries == ["first", "second"])
    }

    @Test("build() rethrows BuildErrors from steps without wrapping them")
    func buildRethrowsBuildErrors() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
            .addStep(FailingStep(name: "Failing step", error: BuildError.missingPath("/missing")))

        do {
            try site.build()
            Issue.record("Expected build() to throw")
        } catch let error as BuildError {
            #expect(error == .missingPath("/missing"))
        } catch {
            Issue.record("Expected a BuildError, got \(error)")
        }
    }

    @Test("build() wraps errors that are not BuildErrors with the failing step's name")
    func buildWrapsNonBuildErrors() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
            .addStep(FailingStep(name: "Failing step", error: TestFailure()))

        do {
            try site.build()
            Issue.record("Expected build() to throw")
        } catch let error as BuildError {
            #expect(error == .stepFailed(step: "Failing step", underlying: TestFailure()))
        } catch {
            Issue.record("Expected a BuildError, got \(error)")
        }
    }

    @Test("rebuild() re-runs non-terminal steps without wiping the output")
    func rebuildRerunsNonTerminalStepsInPlace() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("kept", at: "build/kept.html", relativeTo: virtualRoot, in: fileSystem)
        let recorder = StepRecorder()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
            .addStep(RecordingStep(label: "work", recorder: recorder))
            .addStep(TerminalStep(label: "terminal", recorder: recorder))

        try site.rebuild()

        #expect(try readFile(at: "build/kept.html", relativeTo: virtualRoot, in: fileSystem) == "kept")
        #expect(recorder.entries == ["work"])
    }

    @Test("rebuild() rethrows BuildErrors from steps without wrapping them")
    func rebuildRethrowsBuildErrors() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
            .addStep(FailingStep(name: "Failing step", error: BuildError.missingPath("/missing")))

        #expect(throws: BuildError.missingPath("/missing")) {
            try site.rebuild()
        }
    }
}

/// Records the labels of the steps that run, in order.
private final class StepRecorder: @unchecked Sendable {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// A step that records its label when it runs.
private struct RecordingStep: BuildStep {
    let label: String
    let recorder: StepRecorder

    var name: String { label }

    func run(site: Site) throws {
        recorder.record(label)
    }
}

/// A step that records its label when it runs and is skipped by rebuilds.
private struct TerminalStep: BuildStep {
    let label: String
    let recorder: StepRecorder

    var name: String { label }

    var isTerminal: Bool { true }

    func run(site: Site) throws {
        recorder.record(label)
    }
}

/// A step that always throws a fixed error.
private struct FailingStep: BuildStep {
    let name: String
    let error: any Error

    func run(site: Site) throws {
        throw error
    }
}

/// A plain error used to test error wrapping.
private struct TestFailure: Error {}
