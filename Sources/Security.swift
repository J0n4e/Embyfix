import Foundation

// Small security helpers shared by both themes.

/// Links that come from the server's metadata (trailers, external links) are opened only when they are web
/// links. Anything else (file://, smb://, other apps' URL schemes) could make macOS mount a share or launch an app.
enum SafeLink {
    static func url(_ s: String?) -> URL? {
        guard let s, let u = URL(string: s.trimmingCharacters(in: .whitespaces)),
              let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              u.host?.isEmpty == false else { return nil }
        return u
    }
}

/// The URLSession for talking to the media server. Follows redirects only to the same host (and never from
/// https down to http), so the token in our headers and links can't be forwarded to another server.
enum Net {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        return URLSession(configuration: cfg, delegate: SameHostRedirects(), delegateQueue: nil)
    }()

    /// Same scheme family, host and port (http and https count as different ports when no port is given).
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        func port(_ u: URL) -> Int { u.port ?? (u.scheme?.lowercased() == "https" ? 443 : 80) }
        return a.host?.lowercased() == b.host?.lowercased() && port(a) == port(b)
    }
}

final class SameHostRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let from = task.originalRequest?.url ?? response.url, let to = request.url else { completionHandler(nil); return }
        let downgrade = from.scheme?.lowercased() == "https" && to.scheme?.lowercased() != "https"
        // Allow an upgrade to https on the same host (port changes from 80 to 443 there)
        let upgrade = from.scheme?.lowercased() == "http" && to.scheme?.lowercased() == "https"
            && from.host?.lowercased() == to.host?.lowercased()
        // nil = don't follow; the caller gets the redirect response itself (and treats it as a failure)
        completionHandler(!downgrade && (Net.sameOrigin(from, to) || upgrade) ? request : nil)
    }
}

/// Player debug log at ~/Library/Logs/Cove.log. Off unless switched on in Settings → Playback; kept under
/// about 1 MB (the previous part is moved to Cove.old.log).
enum DebugLog {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "debugLog") }
    private static let maxBytes = 1_000_000
    private static let lock = NSLock()
    private static var dir: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs") }

    static func write(_ m: String) {
        guard enabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(m)\n"
        let u = dir.appendingPathComponent("Cove.log"), old = dir.appendingPathComponent("Cove.old.log")
        lock.withLock {
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: u.path))?[.size] as? Int, size > maxBytes {
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: u, to: old)
            }
            if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? Data(line.utf8).write(to: u) }
        }
    }
}
