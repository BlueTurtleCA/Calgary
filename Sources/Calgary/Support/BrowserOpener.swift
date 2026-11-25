//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// BrowserOpener.swift
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Opens a URL in the default browser, best-effort.
///
/// A browser launch never fails the step that called it: on Apple
/// platforms the system API is used directly, and elsewhere the launch
/// is delegated to the site's command runner (`cmd /c start` on Windows,
/// `xdg-open` on Linux). Any failure — no launcher on the platform, or a
/// launcher that cannot start — is silently skipped.
enum BrowserOpener {
    /// Opens `url` in the default browser.
    ///
    /// - Parameters:
    ///   - url: The URL to open.
    ///   - commandRunner: The runner used to launch the browser on
    ///     non-Apple platforms.
    ///   - workingDirectory: The directory the launcher runs with.
    static func open(url: URL, commandRunner: any CommandRunner, workingDirectory: URL) {
        #if canImport(AppKit)
        _ = NSWorkspace.shared.open(url)
        #elseif os(Windows)
        // `start` treats the first quoted argument as a window title, so an
        // empty title precedes the URL.
        _ = try? commandRunner.run(
            command: "cmd",
            arguments: ["/c", "start", "", url.absoluteString],
            workingDirectory: workingDirectory
        )
        #else
        _ = try? commandRunner.run(
            command: "xdg-open",
            arguments: [url.absoluteString],
            workingDirectory: workingDirectory
        )
        #endif
    }
}
