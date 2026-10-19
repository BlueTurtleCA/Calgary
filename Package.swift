// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Calgary",
    products: [
        .library(name: "Calgary", targets: ["Calgary"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "Calgary",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
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
