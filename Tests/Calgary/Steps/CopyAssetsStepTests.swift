//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// CopyAssetsStepTests.swift
//

import Foundation
import Testing
@testable import Calgary

@Suite("CopyAssetsStep")
struct CopyAssetsStepTests {
    @Test("Copies the contents of the assets directory into the output directory")
    func copiesAssetsPreservingRelativePaths() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("body { margin: 0; }", at: "assets/css/site.css", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("png-bytes", at: "assets/images/logo.png", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("hello", at: "assets/notes.txt", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try site.copyAssets(from: "assets").build()

        #expect(try readFile(at: "build/css/site.css", relativeTo: virtualRoot, in: fileSystem) == "body { margin: 0; }")
        #expect(try readFile(at: "build/images/logo.png", relativeTo: virtualRoot, in: fileSystem) == "png-bytes")
        #expect(try readFile(at: "build/notes.txt", relativeTo: virtualRoot, in: fileSystem) == "hello")
    }

    @Test("Copies hidden files")
    func copiesHiddenFiles() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("hidden", at: "assets/.hidden", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try site.copyAssets(from: "assets").build()

        #expect(try readFile(at: "build/.hidden", relativeTo: virtualRoot, in: fileSystem) == "hidden")
    }

    @Test("Overwrites files that already exist in the destination")
    func overwritesExistingFiles() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("fresh", at: "assets/file.txt", relativeTo: virtualRoot, in: fileSystem)
        try writeFile("stale", at: "build/file.txt", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try CopyAssetsStep(from: "assets").run(site: site)

        #expect(try readFile(at: "build/file.txt", relativeTo: virtualRoot, in: fileSystem) == "fresh")
    }

    @Test("Copies nothing when the assets directory is empty")
    func copiesNothingWhenAssetsDirectoryIsEmpty() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(
            at: virtualRoot.appendingPathComponent("assets"),
            withIntermediateDirectories: true
        )

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        try site.copyAssets(from: "assets").build()

        let contents = try fileSystem.contentsOfDirectory(at: site.outputDirectory)
        #expect(contents.isEmpty)
    }

    @Test("Throws when the assets directory does not exist")
    func throwsWhenAssetsDirectoryIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        let expectedError = BuildError.missingPath(virtualRoot.appendingPathComponent("assets").path)

        #expect(throws: expectedError) {
            try CopyAssetsStep(from: "assets").run(site: site)
        }
    }

    @Test("Throws when the assets path is a file")
    func throwsWhenAssetsPathIsAFile() throws {
        let fileSystem = InMemoryFileSystem()
        try writeFile("not a directory", at: "assets", relativeTo: virtualRoot, in: fileSystem)

        let site = Site(name: "Test Site", root: virtualRoot, fileSystem: fileSystem)
        let expectedError = BuildError.unexpectedPathType(
            path: virtualRoot.appendingPathComponent("assets").path,
            expected: "directory"
        )

        #expect(throws: expectedError) {
            try CopyAssetsStep(from: "assets").run(site: site)
        }
    }

    @Test("Describes itself with the assets directory it copies")
    func nameIncludesAssetsDirectory() {
        #expect(CopyAssetsStep(from: "assets").name == "Copy assets from 'assets'")
    }
}
