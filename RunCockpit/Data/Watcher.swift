import Foundation
import CoreServices

/// FSEvents watcher on `sessions/` and `projects/`. Zero polling.
/// Coalesces bursts and delivers a single debounced callback on the main queue.
final class Watcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private var debounce: DispatchWorkItem?

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func start() {
        guard stream == nil else { return }
        let paths = [Paths.sessionsDir.path, Paths.projectsDir.path] as CFArray
        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue().fire()
        }
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, cb, &ctx, paths,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          0.1, flags) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil
    }

    private func fire() {
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: w)
    }

    deinit { stop() }
}
