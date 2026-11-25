//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// OpenSiteStepTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("OpenSiteStep")
struct OpenSiteStepTests {
    /// A site whose command runner stands in for the browser launcher, so
    /// a test never launches a real browser. The runner records the
    /// launch invocation.
    private func makeSite(fileSystem: InMemoryFileSystem) -> (site: Site, runner: MockCommandRunner) {
        let runner = MockCommandRunner { _, _, _ in commandResult() }
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem, commandRunner: runner)
        return (site, runner)
    }

    @Test("Throws when the page does not exist in the output directory")
    func throwsWhenPageIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let (site, _) = makeSite(fileSystem: fileSystem)

        #expect(throws: BuildError.missingPath(virtualRoot.appendingPathComponent("build/index.html").path)) {
            try OpenSiteStep(page: "index.html").run(site: site)
        }
    }

    @Test("Succeeds when the page exists")
    func succeedsWhenPageExists() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("<html></html>", at: "build/index.html", relativeTo: virtualRoot, in: fileSystem)
        let (site, runner) = makeSite(fileSystem: fileSystem)

        try OpenSiteStep(page: "index.html").run(site: site)
        #if !canImport(AppKit)
        // On Apple platforms the browser opens through the system API, not
        // the runner; elsewhere the runner launches the browser.
        #expect(runner.invocations.count == 1)
        #endif
    }

    @Test("Describes itself with the page it opens")
    func nameIncludesPage() {
        #expect(OpenSiteStep(page: "index.html").name == "Open 'index.html'")
    }

    @Test("Opening is a terminal step")
    func openIsTerminal() {
        #expect(OpenSiteStep(page: "index.html").isTerminal)
    }
}
