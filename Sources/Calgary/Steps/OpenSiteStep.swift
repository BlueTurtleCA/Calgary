//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// OpenSiteStep.swift
//

import Foundation

/// A build step that opens a built page in the default browser.
struct OpenSiteStep: BuildStep {
    /// The page to open, relative to the output directory.
    let page: String

    init(page: String = "index.html") {
        self.page = page
    }

    var name: String {
        "Open '\(page)'"
    }

    var isTerminal: Bool { true }

    func run(site: Site) throws {
        let url = site.outputDirectory.appendingPathComponent(page)
        guard site.fileSystem.fileExists(atPath: url.path) else {
            throw BuildError.missingPath(url.path)
        }
        BrowserOpener.open(
            url: url,
            commandRunner: site.commandRunner,
            workingDirectory: site.root
        )
    }
}
