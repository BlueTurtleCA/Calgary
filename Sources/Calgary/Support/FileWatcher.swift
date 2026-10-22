import Foundation
#if os(macOS) || os(iOS)
import CoreServices
#endif

/// Watches a set of directories for file changes, reporting coalesced
/// batches of changed paths.
///
/// The watcher uses FSEvents, which reports changes at the directory level.
/// Changed paths are accumulated on the watcher's serial queue and delivered
/// to `onChange` at most once per debounce interval, so a burst of changes
/// (for example, a file save) produces a single callback. `onChange` runs on
/// that same queue, so successive calls never overlap.
final class FileWatcher: @unchecked Sendable {
    /// The directories to watch.
    private let paths: [URL]

    /// The interval between the last change and the delivery of the batch.
    private let debounce: TimeInterval

    /// Called with the paths that changed since the last call.
    private let onChange: @Sendable (Set<String>) -> Void

    /// The serial queue that accumulates events and runs `onChange`.
    private let queue = DispatchQueue(label: "Calgary.FileWatcher")

    /// Paths changed since the last delivery, awaiting the debounce.
    private var pendingPaths: Set<String> = []

    /// The scheduled delivery of the pending paths, if any.
    private var pendingWork: DispatchWorkItem?

    #if os(macOS) || os(iOS)
    private var stream: FSEventStreamRef?
    private var contextInfo: UnsafeMutableRawPointer?
    #endif

    /// Creates a watcher.
    ///
    /// - Parameters:
    ///   - paths: The directories to watch.
    ///   - debounce: The interval between the last change and the delivery
    ///     of the batch. Defaults to 0.25 seconds.
    ///   - onChange: Called on the watcher's queue with the paths that
    ///     changed since the last call.
    init(
        paths: [URL],
        debounce: TimeInterval = 0.25,
        onChange: @escaping @Sendable (Set<String>) -> Void
    ) {
        self.paths = paths
        self.debounce = debounce
        self.onChange = onChange
    }

    /// Starts watching.
    func start() {
        #if os(macOS) || os(iOS)
        guard stream == nil else { return }

        // The FSEvents callback can only pass an opaque pointer, so the
        // watcher is carried in a heap-allocated context that the stream
        // retains and `stop()` releases.
        let context = FileWatcherContext(watcher: self)
        let info = Unmanaged.passRetained(context).toOpaque()
        contextInfo = info

        var fseventContext = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            FileWatcher.fseventsCallback,
            &fseventContext,
            paths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0,
            flags
        ) else { return }
        self.stream = stream
        // The callback is invoked on the watcher's queue, so events are
        // accumulated on the same queue that runs `onChange`.
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        #endif
    }

    /// Stops watching and releases the FSEvents stream.
    func stop() {
        #if os(macOS) || os(iOS)
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            if let info = contextInfo {
                Unmanaged<FileWatcherContext>.fromOpaque(info).release()
                contextInfo = nil
            }
        }
        #endif
    }

    /// Accumulates a batch of changed paths and schedules its delivery.
    ///
    /// Called from the FSEvents callback on the watcher's queue.
    func handle(changedPaths: Set<String>) {
        guard !changedPaths.isEmpty else { return }
        pendingPaths.formUnion(changedPaths)
        scheduleDelivery()
    }

    private func scheduleDelivery() {
        guard pendingWork == nil else { return }
        let work = DispatchWorkItem { [self] in
            pendingWork = nil
            let paths = pendingPaths
            pendingPaths = []
            onChange(paths)
        }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    #if os(macOS) || os(iOS)
    /// The FSEvents stream callback.
    ///
    /// FSEvents calls this on the watcher's queue with a C array of changed
    /// paths; it hands them to the watcher.
    private static let fseventsCallback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
        guard let info else { return }
        let context = Unmanaged<FileWatcherContext>.fromOpaque(info).takeUnretainedValue()
        var changed: Set<String> = []
        if eventPaths != nil {
            let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            if let paths = cfPaths as? [String] {
                changed.formUnion(paths)
            }
        }
        context.watcher.handle(changedPaths: changed)
    }
    #endif
}

/// Carries a reference to the watcher into the FSEvents callback, which can
/// only pass an opaque pointer.
private final class FileWatcherContext {
    let watcher: FileWatcher

    init(watcher: FileWatcher) {
        self.watcher = watcher
    }
}
