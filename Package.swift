// swift-tools-version: 6.4

//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// Package.swift
//

// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Calgary",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Calgary", targets: ["Calgary"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        // 2.102.0 is the first release whose targets all build on Windows
        // under the upstream CI; earlier releases fail to compile there.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.102.0"),
    ],
    targets: [
        .target(
            name: "Calgary",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "Example",
            dependencies: ["Calgary"],
            // The sample site's content lives next to the pipeline file;
            // it is read at runtime, not compiled into the executable.
            exclude: [
                "assets",
                "components",
                "content",
                "strings",
                "templates",
                "build",
                "node_modules",
                "package.json",
                "package-lock.json",
            ]
        ),
        .testTarget(
            name: "CalgaryTests",
            dependencies: ["Calgary"],
            path: "Tests/Calgary"
        ),
    ]
)
