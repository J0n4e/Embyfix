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
    struct UD: Decodable, Hashable { let Played: Bool?; let IsFavorite: Bool?; let PlayedPercentage: Double? }
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
    var id: String { item.id }
    var transcode: Bool { audio != nil || sub != nil || maxBitrate != nil }
}

struct MStream: Decodable, Identifiable {
    let Index: Int
    let `Type`: String?
    let DisplayTitle: String?
    let IsDefault: Bool?
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
    var loggedIn: Bool { !token.isEmpty }

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
    }

    private var authHeader: String {
        "MediaBrowser Client=\"EmbyFlix\", Device=\"Mac\", DeviceId=\"\(deviceId)\", Version=\"1.0\""
    }

    func login(server raw: String, user: String, pw: String) async throws {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if !s.hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
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
        server = s; token = t; userId = u
        d.set(s, forKey: "server"); d.set(t, forKey: "token"); d.set(u, forKey: "uid")
    }

    func logout() {
        playing = nil; libs = []; played = [:]; faved = [:]
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

    func children(_ parentId: String) async -> [Item] {
        let r: ItemList? = try? await get("/Users/\(userId)/Items", ["ParentId": parentId, "Fields": "Overview", "SortBy": "SortName"])
        return r?.Items ?? []
    }

    // MARK: Watched / favorites / play

    func isPlayed(_ it: Item) -> Bool { played[it.id] ?? it.UserData?.Played ?? false }
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
        await send(v ? "POST" : "DELETE", "/Users/\(userId)/PlayedItems/\(id)")
    }
    func setFav(_ id: String, _ v: Bool) async {
        faved[id] = v
        await send(v ? "POST" : "DELETE", "/Users/\(userId)/FavoriteItems/\(id)")
    }
    func play(_ it: Item) async {
        if it.isSeries {
            let eps = await episodes(it.id)
            if let e = eps.first(where: { !isPlayed($0) }) ?? eps.first { playing = PlayRequest(item: e) }
        } else if it.isBox {
            if let f = await children(it.id).first { playing = PlayRequest(item: f) }
        } else { playing = PlayRequest(item: it) }
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
            if let t = src["TranscodingUrl"] as? String { return absolute(t) }
            if let t = src["DirectStreamUrl"] as? String { return absolute(t) }
        }
        return URL(string: "\(server)/Videos/\(id)/master.m3u8?MediaSourceId=\(req.sourceId ?? id)&DeviceId=\(deviceId)&VideoCodec=h264&AudioCodec=aac&api_key=\(token)")
    }
}
