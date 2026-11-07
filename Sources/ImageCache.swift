import SwiftUI
import AppKit

/// Pictures from the server, kept in memory while Cove runs and on disk (~/Library/Caches/Cove/Images) between
/// launches, so posters and banners seen before appear at once. Links carry the server's image tag, which
/// changes when the artwork changes, so a saved copy is used without asking the server again.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, NSImage>()
    let urlCache: URLCache
    private let session: URLSession
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let lock = NSLock()

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cove/Images", isDirectory: true)
    }

    private init() {
        memory.totalCostLimit = 200 * 1024 * 1024   // decoded pictures, about 200 MB
        urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 500 * 1024 * 1024,
                            directory: Self.directory)
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = urlCache
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.timeoutIntervalForRequest = 60
        session = URLSession(configuration: cfg)
    }

    /// Already decoded and in memory (no waiting, no flash).
    func cached(_ url: URL) -> NSImage? { memory.object(forKey: url as NSURL) }

    func image(_ url: URL) async -> NSImage? {
        if let m = cached(url) { return m }
        let (task, isNew) = lock.withLock { () -> (Task<NSImage?, Never>, Bool) in
            if let t = inFlight[url] { return (t, false) }
            let t = Task<NSImage?, Never> { [session, memory, urlCache] in
                var r = URLRequest(url: url)
                r.cachePolicy = .returnCacheDataElseLoad
                guard let (data, resp) = try? await session.data(for: r),
                      (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200,
                      let img = NSImage(data: data) else { return nil }
                // Saved copies are kept no matter what caching rules the server sends
                urlCache.storeCachedResponse(CachedURLResponse(response: resp, data: data), for: r)
                memory.setObject(img, forKey: url as NSURL, cost: data.count * 4)
                return img
            }
            inFlight[url] = t
            return (t, true)
        }
        let img = await task.value
        if isNew { lock.withLock { inFlight[url] = nil } }
        return img
    }

    /// Bytes used on disk.
    var diskUsage: Int { urlCache.currentDiskUsage }

    func clear() {
        memory.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }
}

/// Drop-in for SwiftUI's `AsyncImage` that goes through `ImageCache`.
struct CachedImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content
    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        // Pictures already in memory show on the first frame (no grey flash when going back to a page)
        if let url, let img = ImageCache.shared.cached(url) {
            _phase = State(initialValue: .success(Image(nsImage: img)))
        }
    }

    init<I: View, P: View>(url: URL?, @ViewBuilder content: @escaping (Image) -> I,
                           @ViewBuilder placeholder: @escaping () -> P) where Content == _ConditionalContent<I, P> {
        self.init(url: url) { phase in
            if let img = phase.image { content(img) } else { placeholder() }
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else { phase = .empty; return }
                if let img = ImageCache.shared.cached(url) { phase = .success(Image(nsImage: img)); return }
                if case .success = phase {} else { phase = .empty }
                if let img = await ImageCache.shared.image(url) {
                    withAnimation(.easeOut(duration: 0.15)) { phase = .success(Image(nsImage: img)) }
                } else if !Task.isCancelled {
                    phase = .failure(URLError(.cannotDecodeContentData))
                }
            }
    }
}
