//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// CopyAssetsStep.swift
//

import Foundation

/// A build step that copies the contents of an assets directory into the
/// site's output directory, preserving relative paths:
///
/// ```
/// assets/css/site.css    →  build/css/site.css
/// assets/images/logo.png →  build/images/logo.png
/// ```
struct CopyAssetsStep: BuildStep {
    /// The assets directory to copy from, relative to the site's root.
    let from: String

    var name: String {
        "Copy assets from '\(from)'"
    }

    func run(site: Site) throws {
        let fileSystem = site.fileSystem
        let sourceDirectory = site.root.appendingPathComponent(from)

        guard fileSystem.fileExists(atPath: sourceDirectory.path) else {
            throw BuildError.missingPath(sourceDirectory.path)
        }
        guard fileSystem.isDirectory(atPath: sourceDirectory.path) else {
            throw BuildError.unexpectedPathType(path: sourceDirectory.path, expected: "directory")
        }

        try copyContents(of: sourceDirectory, to: site.outputDirectory, fileSystem: fileSystem)
    }

    private func copyContents(of source: URL, to destination: URL, fileSystem: any FileSystem) throws {
        let items = try fileSystem.contentsOfDirectory(at: source)

        for item in items {
            let destinationItem = destination.appendingPathComponent(item.lastPathComponent)

            if fileSystem.isDirectory(atPath: item.path) {
                try fileSystem.createDirectory(at: destinationItem, withIntermediateDirectories: true)
                try copyContents(of: item, to: destinationItem, fileSystem: fileSystem)
            } else {
                if fileSystem.fileExists(atPath: destinationItem.path) {
                    try fileSystem.removeItem(at: destinationItem)
                }
                try fileSystem.copyItem(at: item, to: destinationItem)
            }
        }
    }
}
