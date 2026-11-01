import Foundation

struct Item: Identifiable, Decodable, Hashable {
    let Id: String
    let Name: String
    let `Type`: String?
    let Overview: String?
    let ProductionYear: Int?
    let IndexNumber: Int?
    let ParentIndexNumber: Int?
    let SeriesId: String?
    let SeriesName: String?
    let ParentBackdropItemId: String?
    let BackdropImageTags: [String]?
    let CollectionType: String?
    let UserData: UD?
    struct UD: Decodable, Hashable { let Played: Bool?; let IsFavorite: Bool?; let PlayedPercentage: Double?; let UnplayedItemCount: Int?; let PlaybackPositionTicks: Int64? }
    var id: String { Id }
    var backdropId: String? { (BackdropImageTags ?? []).isEmpty ? ParentBackdropItemId : Id }
    var posterId: String { `Type` == "Episode" ? (SeriesId ?? Id) : Id }
    var heroTitle: String { SeriesName ?? Name }
    var isSeries: Bool { `Type` == "Series" }
    var isBox: Bool { `Type` == "BoxSet" }
    var playable: Bool { !isSeries && !isBox }
    var isEpisode: Bool { `Type` == "Episode" }
}
struct ItemList: Decodable { let Items: [Item]; let TotalRecordCount: Int? }
struct PlayRequest: Identifiable {
    let item: Item
    var sourceId: String?
    var audio: Int?
    var sub: Int?
    var maxBitrate: Int?
    var start: Double? = nil      // seconds to resume from
    var noSub = false             // user chose "Off": don't auto-load the preferred language
    var burnIn = false            // subtitle couldn't be read as text: have the server burn it in
    var id: String { item.id }
    var transcode: Bool { audio != nil || sub != nil || maxBitrate != nil }
}

struct MStream: Decodable, Identifiable {
    let Index: Int
    let `Type`: String?
    let DisplayTitle: String?
    let IsDefault: Bool?
    let Language: String?
    let Codec: String?
    var id: Int { Index }
}
struct MSource: Decodable, Identifiable {
    let Id: String
    let Name: String?
    let Path: String?
    let Container: String?
    let Size: Int64?
    let MediaStreams: [MStream]?
    var id: String { Id }
}
struct Full: Decodable {
    let Genres: [String]?
    let Studios: [Named]?
    let People: [Person]?
    let MediaSources: [MSource]?
    let CommunityRating: Double?
    let CriticRating: Double?
    let OfficialRating: String?
    let RunTimeTicks: Int64?
    let Taglines: [String]?
    let DateCreated: String?
    let ExternalUrls: [Link]?
    let RemoteTrailers: [Link]?
    let UserData: UD?
    struct Named: Decodable { let Name: String }
    struct Person: Decodable, Identifiable {
        let Id: String
        let Name: String
        let Role: String?
        let `Type`: String?
        var id: String { Id + (Role ?? "") }
    }
    struct Link: Decodable { let Name: String?; let Url: String? }
    struct UD: Decodable { let LastPlayedDate: String? }
}

struct Row: Identifiable { let id = UUID(); let title: String; let items: [Item] }

struct LibPref: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var title: String
    var visible: Bool = true     // shown in My Media
    var onHome: Bool = true      // gets a row on the home screen
    var style: String = "latest" // latest | random | top | az
    var kind: String?
}

/// A server the user has signed in to; the token is kept so switching back needs no password.
struct SavedServer: Codable, Identifiable, Hashable {
    var url: String
    var name: String
    var user: String
    var token: String?
    var userId: String?
    var id: String { url.lowercased() }
}

@MainActor
final class Emby: ObservableObject {
    private let d = UserDefaults.standard
    @Published var server = ""
    @Published var token = ""
    @Published var userId = ""
    @Published var libs: [LibPref] = []
    @Published var playing: PlayRequest?
    @Published var played: [String: Bool] = [:]
    @Published var faved: [String: Bool] = [:]
    @Published var servers: [SavedServer] = []
    /// The saved entry for the server we're signed in to.
    var currentServer: SavedServer? { servers.first { $0.id == server.lowercased() } }
    var currentServerName: String {
        if let n = currentServer?.name, !n.isEmpty { return n }
        return URL(string: server)?.host ?? server
    }
    /// Resume positions (seconds) saved during this session; overrides what the server sent with the item.
    @Published var positions: [String: Double] = [:]
    var loggedIn: Bool { !token.isEmpty }

    private func saveServers() {
        if let data = try? JSONEncoder().encode(servers) { d.set(data, forKey: "servers") }
    }

    private func upsert(_ e: SavedServer) {
        if let i = servers.firstIndex(where: { $0.id == e.id }) { servers[i] = e } else { servers.append(e) }
        saveServers()
    }

    func removeServer(_ e: SavedServer) {
        servers.removeAll { $0.id == e.id }
        saveServers()
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Signs in with a remembered token. Returns false if the token no longer works.
    func resume(_ e: SavedServer) async -> Bool {
        guard let t = e.token, let u = e.userId,
              let url = URL(string: "\(e.url)/Users/\(u)") else { return false }
        var r = URLRequest(url: url)
        r.setValue(t, forHTTPHeaderField: "X-Emby-Token")
        r.timeoutInterval = 10
        guard let (_, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200 else {
            var x = e; x.token = nil; x.userId = nil; upsert(x)
            return false
        }
        resetSession()
        server = e.url; token = t; userId = u
        d.set(server, forKey: "server"); d.set(t, forKey: "token"); d.set(u, forKey: "uid")
        return true
    }

    private func serverName(_ s: String) async -> String? {
        guard let u = URL(string: s + "/System/Info/Public"),
              let (data, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return j["ServerName"] as? String
    }

    private func resetSession() {
        playing = nil; libs = []; played = [:]; faved = [:]
    }

    /// Back to the server list, staying signed in on this server.
    func switchServer() {
        resetSession()
        token = ""; userId = ""
        d.removeObject(forKey: "token"); d.removeObject(forKey: "uid")
    }

    let deviceId: String = {
        if let x = UserDefaults.standard.string(forKey: "did") { return x }
        let x = UUID().uuidString
        UserDefaults.standard.set(x, forKey: "did")
        return x
    }()

    init() {
        server = d.string(forKey: "server") ?? ""
        token = d.string(forKey: "token") ?? ""
        userId = d.string(forKey: "uid") ?? ""
        if let data = d.data(forKey: "servers"),
           let list = try? JSONDecoder().decode([SavedServer].self, from: data) { servers = list }
        // Remember the server from before saved servers existed.
        if servers.isEmpty, !server.isEmpty, !token.isEmpty {
            servers = [SavedServer(url: server, name: server, user: "", token: token, userId: userId)]
            saveServers()
        }
    }

    var authHeader: String {
        "MediaBrowser Client=\"EmbyFlix\", Device=\"Mac\", DeviceId=\"\(deviceId)\", Version=\"1.0\""
    }

    func login(server raw: String, user: String, pw: String) async throws {
        let s = Self.normalize(raw)
        var r = URLRequest(url: URL(string: s + "/Users/AuthenticateByName")!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["Username": user, "Pw": pw])
        let (data, _) = try await URLSession.shared.data(for: r)
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = j["AccessToken"] as? String,
              let u = (j["User"] as? [String: Any])?["Id"] as? String
        else { throw URLError(.userAuthenticationRequired) }
        resetSession()
        server = s; token = t; userId = u
        d.set(s, forKey: "server"); d.set(t, forKey: "token"); d.set(u, forKey: "uid")
        let name = await serverName(s) ?? servers.first { $0.id == s.lowercased() }?.name ?? s
        upsert(SavedServer(url: s, name: name, user: user, token: t, userId: u))
    }

    /// Signs out of this server: forgets its token but keeps it (and the username) in the list.
    func logout() {
        if let i = servers.firstIndex(where: { $0.id == server.lowercased() }) {
            servers[i].token = nil; servers[i].userId = nil; saveServers()
        }
        resetSession()
        token = ""; userId = ""
        d.removeObject(forKey: "token"); d.removeObject(forKey: "uid")
    }

    func get<T: Decodable>(_ path: String, _ q: [String: String] = [:]) async throws -> T {
        var c = URLComponents(string: server + path)!
        c.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        var r = URLRequest(url: c.url!)
        r.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let (data, _) = try await URLSession.shared.data(for: r)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func image(_ id: String, _ kind: String = "Primary", width: Int = 400) -> URL? {
        URL(string: "\(server)/Items/\(id)/Images/\(kind)?maxWidth=\(width)&api_key=\(token)")
    }

    // MARK: Libraries

    func loadLibs() async {
        guard let v: ItemList = try? await get("/Users/\(userId)/Views") else { return }
        let saved = (try? JSONDecoder().decode([LibPref].self, from: d.data(forKey: "libs-\(userId)") ?? Data())) ?? []
        var out = saved.filter { s in v.Items.contains { $0.Id == s.id } }
        for l in v.Items where !out.contains(where: { $0.id == l.Id }) {
            out.append(LibPref(id: l.Id, name: l.Name, title: l.Name, kind: l.CollectionType))
        }
        for i in out.indices { out[i].kind = v.Items.first(where: { $0.Id == out[i].id })?.CollectionType }
        libs = out
    }

    func saveLibs() {
        d.set(try? JSONEncoder().encode(libs), forKey: "libs-\(userId)")
    }

    func libraryItems(_ lib: LibPref, limit: Int, start: Int = 0, sort: String? = nil, desc: Bool? = nil,
                      watch: String = "all", genre: String = "", letter: String = "", favorites: Bool = false,
                      types: String = "Movie,Series,BoxSet,Video,MusicVideo") async -> ItemList {
        var q = ["ParentId": lib.id, "Fields": "Overview", "Limit": String(limit), "StartIndex": String(start),
                 "Recursive": "true", "IncludeItemTypes": types]
        var by = "DateCreated", down = true
        switch sort ?? lib.style {
        case "name", "az": by = "SortName"; down = false
        case "release": by = "PremiereDate,SortName"
        case "top": by = "CommunityRating"
        case "random": by = "Random"
        default: break
        }
        q["SortBy"] = by
        q["SortOrder"] = (desc ?? down) ? "Descending" : "Ascending"
        var f: [String] = []
        if watch == "unwatched" { f.append("IsUnplayed") }
        if watch == "watched" { f.append("IsPlayed") }
        if favorites { f.append("IsFavorite") }
        if !f.isEmpty { q["Filters"] = f.joined(separator: ",") }
        if !genre.isEmpty { q["Genres"] = genre }
        if letter == "#" { q["NameLessThan"] = "A" } else if !letter.isEmpty { q["NameStartsWith"] = letter }
        let r: ItemList? = try? await get("/Users/\(userId)/Items", q)
        return r ?? ItemList(Items: [], TotalRecordCount: 0)
    }

    func genres(_ lib: LibPref) async -> [String] {
        let r: ItemList? = try? await get("/Genres", ["ParentId": lib.id, "UserId": userId, "SortBy": "SortName", "Recursive": "true"])
        return r?.Items.map { $0.Name } ?? []
    }

    func loadHome() async -> [Row] {
        if libs.isEmpty { await loadLibs() }
        var rows: [Row] = []
        if let r: ItemList = try? await get("/Users/\(userId)/Items/Resume",
            ["Fields": "Overview", "Limit": "20", "MediaTypes": "Video", "Recursive": "true"]),
           !r.Items.isEmpty { rows.append(Row(title: "Continue Watching", items: r.Items)) }
        for lib in libs where lib.visible && lib.onHome {
            let items = await libraryItems(lib, limit: 20).Items
            if !items.isEmpty { rows.append(Row(title: lib.title, items: items)) }
        }
        return rows
    }

    func episodes(_ seriesId: String) async -> [Item] {
        let r: ItemList? = try? await get("/Shows/\(seriesId)/Episodes", ["UserId": userId, "Fields": "Overview"])
        return r?.Items ?? []
    }

    func seasons(_ seriesId: String) async -> [Item] {
        let r: ItemList? = try? await get("/Shows/\(seriesId)/Seasons", ["UserId": userId])
        return r?.Items ?? []
    }

    func children(_ parentId: String) async -> [Item] {
        let r: ItemList? = try? await get("/Users/\(userId)/Items", ["ParentId": parentId, "Fields": "Overview", "SortBy": "SortName"])
        return r?.Items ?? []
    }

    // MARK: Watched / favorites / play

    func isPlayed(_ it: Item) -> Bool { played[it.id] ?? it.UserData?.Played ?? false }
    /// Where to resume an item from, in seconds (0 = start). Ignores the first 30 s.
    /// A saved position wins even if the item is marked watched (e.g. re-watching a movie);
    /// finishing an item or marking it watched in the app clears the position.
    func resumeAt(_ it: Item) -> Double {
        let t = positions[it.id] ?? Double(it.UserData?.PlaybackPositionTicks ?? 0) / 10_000_000
        return t > 30 ? t : 0
    }

    /// Next episode to watch for a series (in progress or first unwatched), as the server sees it.
    func nextUp(_ seriesId: String) async -> Item? {
        let r: ItemList? = try? await get("/Shows/NextUp", ["SeriesId": seriesId, "UserId": userId, "Fields": "Overview", "Limit": "1"])
        return r?.Items.first
    }

    // MARK: Playback progress (lets the server remember where you stopped)

    private func postJSON(_ path: String, _ body: [String: Any]) async {
        guard let url = URL(string: server + path) else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        r.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: r)
    }

    /// One playback as the server tracks it. Emby rejects reports without a PlaySessionId (HTTP 400).
    struct PlaySession {
        let itemId: String
        let sourceId: String?
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let method: String          // DirectPlay | DirectStream | Transcode
    }

    private func progressBody(_ s: PlaySession, _ sec: Double, paused: Bool = false) -> [String: Any] {
        var b: [String: Any] = ["ItemId": s.itemId, "PositionTicks": Int64(max(0, sec) * 10_000_000),
                                "IsPaused": paused, "CanSeek": true,
                                "PlaySessionId": s.id, "PlayMethod": s.method]
        if let sourceId = s.sourceId { b["MediaSourceId"] = sourceId }
        return b
    }

    func reportStart(_ s: PlaySession, _ sec: Double) async {
        await postJSON("/Sessions/Playing", progressBody(s, sec))
    }

    func reportProgress(_ s: PlaySession, _ sec: Double, paused: Bool) async {
        await postJSON("/Sessions/Playing/Progress", progressBody(s, sec, paused: paused))
    }

    func reportStopped(_ s: PlaySession, _ sec: Double, duration: Double) async {
        let finished = duration > 0 && sec / duration > 0.9
        positions[s.itemId] = finished ? 0 : sec
        if finished { played[s.itemId] = true }
        await postJSON("/Sessions/Playing/Stopped", progressBody(s, sec))
    }

    func isFav(_ it: Item) -> Bool { faved[it.id] ?? it.UserData?.IsFavorite ?? false }

    private func send(_ method: String, _ path: String) async {
        guard let url = URL(string: server + path) else { return }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        _ = try? await URLSession.shared.data(for: r)
    }
    func setPlayed(_ id: String, _ v: Bool) async {
        played[id] = v
        positions[id] = 0
        await send(v ? "POST" : "DELETE", "/Users/\(userId)/PlayedItems/\(id)")
    }
    func setFav(_ id: String, _ v: Bool) async {
        faved[id] = v
        await send(v ? "POST" : "DELETE", "/Users/\(userId)/FavoriteItems/\(id)")
    }
    func play(_ it: Item) async {
        if it.isSeries {
            let eps = await episodes(it.id)
            let next = await nextUp(it.id)
            if let e = next ?? eps.first(where: { !isPlayed($0) }) ?? eps.first {
                playing = PlayRequest(item: e, start: resumeAt(e))
            }
        } else if it.isBox {
            if let f = await children(it.id).first { playing = PlayRequest(item: f) }
        } else { playing = PlayRequest(item: it, start: resumeAt(it)) }
    }

    func full(_ id: String) async -> Full? {
        try? await get("/Users/\(userId)/Items/\(id)", ["Fields": "Overview,People,Genres,Studios,MediaSources,MediaStreams,Taglines,DateCreated,ExternalUrls,RemoteTrailers"])
    }

    func similar(_ id: String) async -> [Item] {
        let r: ItemList? = try? await get("/Items/\(id)/Similar", ["UserId": userId, "Limit": "12", "Fields": "Overview"])
        return r?.Items ?? []
    }

    func search(_ term: String) async -> [Item] {
        let r: ItemList? = try? await get("/Users/\(userId)/Items", ["SearchTerm": term, "Recursive": "true", "Limit": "60",
            "IncludeItemTypes": "Movie,Series,BoxSet,Video,MusicVideo,Episode", "Fields": "Overview"])
        return r?.Items ?? []
    }

    // MARK: Playback

    private func absolute(_ path: String) -> URL? {
        var s = path.hasPrefix("http") ? path : server + (path.hasPrefix("/") ? path : "/" + path)
        if !s.contains("api_key=") { s += (s.contains("?") ? "&" : "?") + "api_key=" + token }
        return URL(string: s)
    }

    /// The server ignores the requested subtitle and burns in the user's default track,
    /// so force the chosen track into the transcode URL (or strip subtitles when "Off").
    static func fixSubtitle(_ url: String, _ sub: Int?) -> String {
        guard var c = URLComponents(string: url) else { return url }
        var q = (c.queryItems ?? []).filter { $0.name != "SubtitleStreamIndex" && $0.name != "SubtitleMethod" }
        if let sub {
            q.append(URLQueryItem(name: "SubtitleStreamIndex", value: String(sub)))
            q.append(URLQueryItem(name: "SubtitleMethod", value: "Encode"))
        }
        c.queryItems = q
        return c.string ?? url
    }

    /// Downloads a subtitle track as SRT (the server converts embedded text subs too).
    /// Returns nil for image subtitles (PGS etc.) that can't be converted.
    func subtitleCues(_ itemId: String, _ sourceId: String?, _ index: Int) async -> [Cue]? {
        var sid = sourceId
        if sid == nil { sid = await full(itemId)?.MediaSources?.first?.Id }
        guard let sid, let u = URL(string: "\(server)/Videos/\(itemId)/\(sid)/Subtitles/\(index)/Stream.srt?api_key=\(token)") else { return nil }
        // Embedded subtitles are extracted from the whole video file the first time, which can take minutes.
        var r = URLRequest(url: u)
        r.timeoutInterval = 600
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let cues = Cue.parseSRT(text)
        return cues.isEmpty ? nil : cues
    }

    /// Asks the server how to play the item for AVPlayer: direct play for MP4/MOV, otherwise HLS transcode
    /// (also used whenever a subtitle, a different audio track or a lower quality is chosen).
    func resolveStream(_ req: PlayRequest, direct: Bool = true) async -> URL? {
        let id = req.item.id
        let canDirect = direct && !req.transcode
        let profile: [String: Any] = [
            "Name": "EmbyFlix Mac",
            "MaxStreamingBitrate": req.maxBitrate ?? 120_000_000,
            "DirectPlayProfiles": canDirect
                ? [["Container": "mp4,m4v,mov", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,ac3,eac3,mp3"]]
                : [[String: Any]](),
            "TranscodingProfiles": [["Container": "ts", "Type": "Video", "AudioCodec": "aac", "VideoCodec": "h264",
                                     "Context": "Streaming", "Protocol": "hls", "MaxAudioChannels": "2",
                                     "MinSegments": "1", "BreakOnNonKeyFrames": true]],
            "SubtitleProfiles": ["srt", "subrip", "ass", "ssa", "vtt", "pgs", "pgssub", "dvdsub"].map { ["Format": $0, "Method": "Encode"] }
        ]
        var qi = [URLQueryItem(name: "UserId", value: userId),
                  URLQueryItem(name: "IsPlayback", value: "true"),
                  URLQueryItem(name: "AutoOpenLiveStream", value: "true")]
        if let v = req.sourceId { qi.append(URLQueryItem(name: "MediaSourceId", value: v)) }
        if let v = req.audio { qi.append(URLQueryItem(name: "AudioStreamIndex", value: String(v))) }
        if let v = req.sub { qi.append(URLQueryItem(name: "SubtitleStreamIndex", value: String(v))) }
        if let v = req.maxBitrate { qi.append(URLQueryItem(name: "MaxStreamingBitrate", value: String(v))) }
        var c = URLComponents(string: "\(server)/Items/\(id)/PlaybackInfo")!
        c.queryItems = qi
        var r = URLRequest(url: c.url!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["DeviceProfile": profile])
        if let (data, _) = try? await URLSession.shared.data(for: r),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = j["MediaSources"] as? [[String: Any]],
           let src = list.first(where: { ($0["Id"] as? String) == req.sourceId }) ?? list.first {
            let sid = src["Id"] as? String ?? id
            let cont = (src["Container"] as? String ?? "").lowercased().split(separator: ",").map(String.init)
            if canDirect, src["SupportsDirectPlay"] as? Bool == true,
               cont.contains(where: { ["mp4", "m4v", "mov"].contains($0) }) {
                return URL(string: "\(server)/Videos/\(id)/stream.mp4?Static=true&MediaSourceId=\(sid)&api_key=\(token)")
            }
            if let t = src["TranscodingUrl"] as? String { return absolute(Self.fixSubtitle(t, req.sub)) }
            if let t = src["DirectStreamUrl"] as? String { return absolute(t) }
        }
        return URL(string: "\(server)/Videos/\(id)/master.m3u8?MediaSourceId=\(req.sourceId ?? id)&DeviceId=\(deviceId)&VideoCodec=h264&AudioCodec=aac&api_key=\(token)")
    }
}


/// Subtitle formats the server can only burn into the video (pictures, not text).
let imageSubCodecs: Set<String> = ["pgs", "pgssub", "hdmv_pgs_subtitle", "dvdsub", "dvd_subtitle", "dvbsub", "dvb_subtitle", "vobsub", "xsub"]

/// Preferred-language subtitle track: text formats first, then any.
func preferredSub(_ streams: [MStream], lang: String) -> Int? {
    let subs = streams.filter { $0.`Type` == "Subtitle" && subLangName($0).lowercased() == lang.lowercased() }
    let text = subs.first { !imageSubCodecs.contains(($0.Codec ?? "").lowercased()) }
    return (text ?? subs.first)?.Index
}

/// Language name from "English (SRT)" etc., so "eng" and "en" tracks group together.
func subLangName(_ st: MStream) -> String {
    let t = st.DisplayTitle ?? st.Language ?? "Unknown"
    return t.components(separatedBy: " (").first ?? t
}

struct Cue {
    let start: Double
    let end: Double
    let text: String

    static func parseSRT(_ srt: String) -> [Cue] {
        func secs(_ t: String) -> Double? {
            let p = t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
            guard p.count == 3, let h = Double(p[0]), let m = Double(p[1]), let s = Double(p[2]) else { return nil }
            return h * 3600 + m * 60 + s
        }
        var out: [Cue] = []
        let blocks = srt.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for b in blocks {
            let lines = b.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[ti].components(separatedBy: "-->")
            guard parts.count == 2, let a = secs(parts[0]), let e = secs(String(parts[1].prefix(13))) else { continue }
            let text = lines[(ti + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            if !text.isEmpty { out.append(Cue(start: a, end: e, text: text)) }
        }
        return out.sorted { $0.start < $1.start }
    }
}
