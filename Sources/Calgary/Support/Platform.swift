//
// Calgary
// Copyright (C) 2026 Blue Turtle Corporation
// Author: David Gill
// Platform.swift
//

/// A platform a command runs on.
public enum Platform: String, CaseIterable, Sendable {
    case macOS
    case linux
    case windows

    /// The platform the code is running on.
    public static var current: Platform {
        #if os(Windows)
        return .windows
        #elseif os(macOS)
        return .macOS
        #else
        return .linux
        #endif
    }
}
