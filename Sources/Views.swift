import IOKit.pwr_mgt
import SwiftUI
import AVKit

// MARK: - Theme

private struct BGKey: EnvironmentKey { static let defaultValue = Color.black }
extension EnvironmentValues {
    var appBG: Color {
        get { self[BGKey.self] }
        set { self[BGKey.self] = newValue }
    }
}

enum Theme {
    static let accents: [(String, Color)] = [
        ("red", Color(red: 0.90, green: 0.04, blue: 0.08)), ("orange", .orange), ("pink", .pink),
        ("purple", .purple), ("blue", .blue), ("teal", .teal), ("green", .green)
    ]
    static let backgrounds: [(String, Color)] = [
        ("black", .black), ("charcoal", Color(white: 0.11)), ("navy", Color(red: 0.04, green: 0.07, blue: 0.17)),
        ("plum", Color(red: 0.12, green: 0.05, blue: 0.15)), ("forest", Color(red: 0.04, green: 0.12, blue: 0.08))
    ]
    static func accent(_ n: String) -> Color { accents.first { $0.0 == n }?.1 ?? accents[0].1 }
    static func bg(_ n: String) -> Color { backgrounds.first { $0.0 == n }?.1 ?? .black }
}

extension View {
    func pill(active: Bool = false) -> some View {
        self.font(.callout.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(active ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.1)))
            .clipShape(Capsule())
    }
    func circleButton() -> some View {
        self.font(.title3).frame(width: 44, height: 44)
            .background(Color.white.opacity(0.14)).clipShape(Circle())
    }
}

let alphaLetters: [String] = ["#"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }

func runtimeText(_ t: Int64) -> String {
    let m = Int(t / 600_000_000)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}
func endsAtText(_ t: Int64) -> String {
    Date().addingTimeInterval(Double(t) / 10_000_000).formatted(date: .omitted, time: .shortened)
}
func parseDate(_ s: String?) -> Date? {
    guard let s, s.count >= 19 else { return nil }
    return ISO8601DateFormatter().date(from: String(s.prefix(19)) + "Z")
}

struct RootView: View {
    @EnvironmentObject var emby: Emby
    var body: some View {
        ZStack {
            // Hide (but keep) the screen under the player: AppKit controls such as spinners
            // otherwise draw on top of the video.
            Group { if emby.loggedIn { HomeView() } else { LoginView() } }
                .opacity(emby.playing == nil ? 1 : 0)
                .allowsHitTesting(emby.playing == nil)
            if let req = emby.playing {
                PlayerView(req: req).id(req.id).zIndex(10)
            }
        }
        .onChange(of: emby.playing?.id) { _, id in PlaybackFlag.shared.active = id != nil }
    }
}

struct LoginView: View {
    @EnvironmentObject var emby: Emby
    @State private var adding = false
    @State private var server = ""
    @State private var user = ""
    @State private var pw = ""
    @State private var error = ""
    @State private var busy = false
    @FocusState private var focus: Field?
    enum Field { case server, user, pw }

    var showForm: Bool { adding || emby.servers.isEmpty }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("EMBYFLIX").font(.system(size: 44, weight: .black)).foregroundStyle(.tint)
                if showForm { form } else { serverList }
                if !error.isEmpty { Text(error).foregroundColor(.orange).font(.caption).multilineTextAlignment(.center) }
            }
            .frame(width: showForm ? 340 : 520).padding(36)
            .background(Color.black.opacity(0.75)).cornerRadius(8)
            VStack { Spacer(); Text("EmbyFlix \(AppVersion.label)").font(.caption).foregroundColor(.secondary).padding(12) }
        }
    }

    var serverList: some View {
        VStack(spacing: 14) {
            Text("Select Server").font(.title.bold()).padding(.bottom, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                ForEach(emby.servers) { s in serverCard(s) }
                Button { startAdd() } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 34, weight: .light))
                            .frame(width: 150, height: 100)
                            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6])))
                        Text("Add Server").font(.headline)
                        Text(" ").font(.caption)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if busy { Spinner().controlSize(.small) }
        }
    }

    func serverCard(_ s: SavedServer) -> some View {
        Button { open(s) } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "server.rack").font(.system(size: 38))
                        .frame(width: 150, height: 100)
                        .background(Color.white.opacity(0.08)).cornerRadius(10)
                    if s.token != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).padding(6)
                            .help("Signed in")
                    }
                }
                Text(s.name).font(.headline).lineLimit(1)
                Text(s.user.isEmpty ? s.url : "\(s.user) · \(s.url)")
                    .font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(width: 150).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(busy)
        .contextMenu {
            Button("Edit / Sign In Again") { edit(s) }
            Button("Remove Server", role: .destructive) { emby.removeServer(s) }
        }
    }

    var form: some View {
        VStack(spacing: 14) {
            HStack {
                if !emby.servers.isEmpty {
                    Button { adding = false; error = "" } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).help("Back to servers")
                }
                Spacer()
                Text(emby.servers.isEmpty ? "Sign In" : "Add Server").font(.title.bold())
                Spacer()
                if !emby.servers.isEmpty { Image(systemName: "chevron.left").hidden() }
            }.padding(.bottom, 6)
            TextField("Server (e.g. 192.168.1.10:8096)", text: $server).focused($focus, equals: .server)
                .onSubmit { focus = .user }
            TextField("Username", text: $user).focused($focus, equals: .user).onSubmit { focus = .pw }
            SecureField("Password", text: $pw).focused($focus, equals: .pw).onSubmit(go)
            Button(action: go) {
                HStack {
                    if busy { Spinner().controlSize(.small) }
                    Text("Sign In").bold()
                }.frame(maxWidth: .infinity).padding(8)
            }.buttonStyle(.borderedProminent).disabled(busy || server.isEmpty || user.isEmpty)
        }
        .textFieldStyle(.roundedBorder).controlSize(.large)
        .onAppear { focus = server.isEmpty ? .server : .pw }
    }

    func startAdd() { server = ""; user = ""; pw = ""; error = ""; adding = true }

    func edit(_ s: SavedServer) { server = s.url; user = s.user; pw = ""; error = ""; adding = true; focus = .pw }

    func open(_ s: SavedServer) {
        error = ""
        guard s.token != nil else { edit(s); return }
        busy = true
        Task {
            let ok = await emby.resume(s)
            busy = false
            if !ok { edit(s); error = "Session expired. Enter your password to sign in again." }
        }
    }

    func go() {
        guard !busy else { return }
        busy = true; error = ""
        Task {
            do { try await emby.login(server: server, user: user, pw: pw); pw = ""; adding = false }
            catch { self.error = "Couldn't sign in. Check server address and credentials." }
            busy = false
        }
    }
}

// MARK: - Sidebar shell + search

struct HomeView: View {
    @EnvironmentObject var emby: Emby
    @State private var sel = "home"
    @State private var activeCount = 0
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showSettings = false
    @State private var reloadToken = 0

    func icon(_ lib: LibPref) -> String {
        switch lib.kind {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "boxsets": return "square.stack"
        case "music": return "music.note"
        case "homevideos": return "video"
        default: return "folder"
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $sel) {
                Label("Home", systemImage: "house.fill").tag("home")
                Label("Favorites", systemImage: "heart.fill").tag("favorites")
                Label("Now Playing", systemImage: "dot.radiowaves.left.and.right")
                    .badge(activeCount)
                    .tag("nowplaying")   // tag last, or the badge hides it and the row can't be selected
                Section("My Media") {
                    ForEach(emby.libs.filter { $0.visible }) { lib in
                        Label(lib.title, systemImage: icon(lib)).tag(lib.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 280)
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EMBYFLIX").font(.system(size: 20, weight: .black)).foregroundStyle(.tint)
                        Text(AppVersion.label).font(.caption2).foregroundColor(.secondary)
                    }.padding(.horizontal, 4)
                    Button { emby.switchServer() } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(emby.currentServerName).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(emby.currentServer?.user.isEmpty == false ? emby.currentServer!.user : (URL(string: emby.server)?.host ?? ""))
                                    .font(.caption2).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .cornerRadius(8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Connected to \(emby.server) — click to switch server")
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape").font(.callout)
                            .padding(.horizontal, 8).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .help("Settings (⌘,)").keyboardShortcut(",", modifiers: .command)
                    Spacer()
                    Button("Sign Out") { emby.logout() }.font(.caption).foregroundColor(.secondary)
                }.buttonStyle(.plain).padding(10)
            }
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if !query.isEmpty { SearchView(query: query) }
                    else if sel == "home" { HomeContent(reloadToken: reloadToken) }
                    else if sel == "favorites" { FavoritesView() }
                    else if sel == "nowplaying" { NowPlayingView() }
                    else if let lib = emby.libs.first(where: { $0.id == sel }) { LibraryView(lib: lib).id(lib.id) }
                    else { Color.black }
                }
                .navigationDestination(for: Item.self) { DetailView(item: $0) }
                .navigationDestination(for: PersonRef.self) { PersonView(person: $0) }
            }
            .safeAreaInset(edge: .top, spacing: 0) { SearchBar(query: $query) }
        }
        .task { await emby.loadLibs() }
        .task {
            // Keep the sidebar's Now Playing count fresh
            while !Task.isCancelled {
                activeCount = await emby.nowPlaying().count
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .onChange(of: sel) { path = NavigationPath(); query = "" }
        .sheet(isPresented: $showSettings) { SettingsView { reloadToken += 1 } }
    }
}

struct SearchBar: View {
    @Binding var query: String
    @Environment(\.appBG) var bg
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search movies, shows, people", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 280)
        }
        .padding(.horizontal, 32).padding(.vertical, 10)
        .background(bg)
    }
}

struct SearchView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    let query: String
    @State private var results: [Item] = []
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Results for “\(query)”").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                    ForEach(results) { PosterCard(item: $0) }
                }
                if busy { Spinner() }
                else if results.isEmpty { Text("No results").foregroundColor(.secondary) }
            }.padding(40)
        }
        .background(bg)
        .task(id: query) {
            busy = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            results = await emby.search(query)
            busy = false
        }
    }
}

// MARK: - Favorites

/// Movies and shows marked as favorite, in two sections. Refreshes each time the page is shown,
/// and hides anything un-favorited from the detail page right away.
struct FavoritesView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    @State private var items: [Item] = []
    @State private var loading = true

    var body: some View {
        let favs = items.filter { emby.isFav($0) }
        let movies = favs.filter { !$0.isSeries }
        let shows = favs.filter { $0.isSeries }
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Favorites").font(.title.bold())
                    if !favs.isEmpty { Text("\(favs.count) Items").foregroundColor(.secondary) }
                }
                if !movies.isEmpty { section("Movies", movies) }
                if !shows.isEmpty { section("Shows", shows) }
                if loading && items.isEmpty { Spinner().frame(maxWidth: .infinity).padding(60) }
                else if favs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart").font(.system(size: 40)).foregroundColor(.secondary)
                        Text("No favorites yet").font(.headline)
                        Text("Tap the heart on a movie or show to add it here.").foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
        }
        .background(bg)
        .onAppear { Task { items = await emby.favorites(); loading = false } }
    }

    func section(_ title: String, _ list: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], alignment: .leading, spacing: 22) {
                ForEach(list) { PosterCard(item: $0) }
            }
        }
    }
}

// MARK: - Now Playing (active sessions on the server)

struct NowPlayingView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    @State private var sessions: [ActiveSession] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Now Playing").font(.title.bold())
                    if !sessions.isEmpty { Text("\(sessions.count) active").foregroundColor(.secondary) }
                }
                if !loaded { Spinner().frame(maxWidth: .infinity).padding(60) }
                else if sessions.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "play.slash").font(.system(size: 40)).foregroundColor(.secondary)
                        Text("Nothing is playing right now").font(.headline)
                    }.frame(maxWidth: .infinity).padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18)], alignment: .leading, spacing: 18) {
                        ForEach(sessions) { SessionCard(s: $0) }
                    }
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
        }
        .background(bg)
        .task {
            while !Task.isCancelled {
                sessions = await emby.nowPlaying()
                loaded = true
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

struct SessionCard: View {
    @EnvironmentObject var emby: Emby
    let s: ActiveSession

    func clock(_ ticks: Int64?) -> String { timeString(Double(ticks ?? 0) / 10_000_000) }

    var icon: String {
        let c = (s.Client ?? "").lowercased() + " " + (s.DeviceName ?? "").lowercased()
        if c.contains("embyflix") || c.contains("mac") { return "desktopcomputer" }
        if c.contains("web") || c.contains("chrome") || c.contains("firefox") || c.contains("safari") { return "globe" }
        if c.contains("iphone") || c.contains("ios") || c.contains("android") { return "iphone" }
        if c.contains("tv") || c.contains("roku") || c.contains("kodi") { return "tv" }
        return "display"
    }

    var body: some View {
        let it = s.NowPlayingItem!
        let pos = Double(s.PlayState?.PositionTicks ?? 0), dur = Double(it.RunTimeTicks ?? 0)
        let transcoding = s.PlayState?.PlayMethod == "Transcode"
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: emby.image(it.SeriesId ?? it.Id, width: 160)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.white.opacity(0.08) }
                .frame(width: 64, height: 96).clipped().cornerRadius(4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(it.SeriesName ?? it.Name).font(.headline).lineLimit(1)
                    if it.SeriesName != nil {
                        Text("S\(it.ParentIndexNumber ?? 0):E\(it.IndexNumber ?? 0) - \(it.Name)")
                            .foregroundColor(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if s.PlayState?.IsPaused == true { Image(systemName: "pause.fill").font(.caption) }
                        Text("\(clock(s.PlayState?.PositionTicks)) / \(clock(it.RunTimeTicks))").monospacedDigit()
                    }.foregroundColor(.secondary)
                    Text(transcoding ? "Transcode" : "Direct play")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(transcoding ? Color.orange.opacity(0.25) : Color.green.opacity(0.25)))
                        .help(s.TranscodingInfo?.TranscodeReasons?.joined(separator: ", ") ?? "")
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            // Progress: watched position, plus how far the server has transcoded
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.15))
                    if let c = s.TranscodingInfo?.CompletionPercentage {
                        Rectangle().fill(Color.white.opacity(0.3)).frame(width: g.size.width * min(1, c / 100))
                    }
                    Rectangle().fill(Color.accentColor).frame(width: dur > 0 ? g.size.width * min(1, pos / dur) : 0)
                }
            }.frame(height: 4)
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 26)).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(s.Client ?? "Unknown") \(s.ApplicationVersion ?? "")").font(.callout.weight(.semibold))
                    Text([s.DeviceName, s.UserName].compactMap { $0 }.joined(separator: " · ")).foregroundColor(.secondary)
                    if let ip = s.RemoteEndPoint { Text(ip).font(.caption).foregroundColor(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }
}

// MARK: - Person

struct PersonRef: Hashable { let id: String; let name: String }

/// Everything in the user's libraries featuring one actor / director.
struct PersonView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    let person: PersonRef
    @State private var items: [Item] = []
    @State private var bio = ""
    @State private var loading = true
    @State private var showBio = false

    var body: some View {
        let movies = items.filter { !$0.isSeries }
        let shows = items.filter { $0.isSeries }
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !movies.isEmpty { section("Movies", movies) }
                if !shows.isEmpty { section("Shows", shows) }
                if loading { Spinner().frame(maxWidth: .infinity).padding(60) }
                else if items.isEmpty {
                    Text("Nothing in your libraries with \(person.name).").foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
        }
        .background(bg)
        .navigationTitle(person.name)
        .task {
            async let list = emby.itemsWithPerson(person.id)
            async let me = emby.person(person.id)
            items = await list
            bio = await me?.Overview ?? ""
            loading = false
        }
    }

    var header: some View {
        HStack(alignment: .top, spacing: 24) {
            AsyncImage(url: emby.image(person.id, width: 300)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack { Color(white: 0.18); Image(systemName: "person.fill").font(.system(size: 50)).foregroundColor(.secondary) }
            }
            .frame(width: 140, height: 140).clipShape(Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(person.name).font(.largeTitle.bold())
                if !loading {
                    Text("\(items.count) title\(items.count == 1 ? "" : "s") in your libraries").foregroundColor(.secondary)
                }
                if !bio.isEmpty {
                    Text(bio).foregroundColor(.secondary).lineLimit(showBio ? nil : 4).textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                    Button(showBio ? "Less" : "More") { showBio.toggle() }.buttonStyle(.plain).foregroundColor(.accentColor)
                }
            }
        }
    }

    func section(_ title: String, _ list: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(title) (\(list.count))").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], alignment: .leading, spacing: 22) {
                ForEach(list) { PosterCard(item: $0) }
            }
        }
    }
}

// MARK: - Home

struct HomeContent: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    let reloadToken: Int
    @State private var rows: [Row] = []
    @State private var loading = true

    var heroItems: [Item] {
        var seen = Set<String>()
        var out: [Item] = []
        for row in rows {
            for it in row.items.filter({ $0.backdropId != nil }).prefix(2) where !seen.contains(it.heroTitle) {
                seen.insert(it.heroTitle); out.append(it)
            }
        }
        return Array(out.prefix(8))
    }

    var body: some View {
        let hero = heroItems
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !hero.isEmpty { Hero(items: hero) }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(row.title).font(.title3.bold()).padding(.leading, 32)
                        if row.title == "Continue Watching" {
                            ArrowScrollRow(ids: Array(row.items.indices), itemWidth: 260, spacing: 14, inset: 32) {
                                ResumeCard(item: row.items[$0])
                            }
                        } else {
                            ArrowScrollRow(ids: Array(row.items.indices), itemWidth: 150, spacing: 14, inset: 32) {
                                PosterCard(item: row.items[$0])
                            }
                        }
                    }
                }
                if loading { Spinner().frame(maxWidth: .infinity).padding(60) }
            }.padding(.bottom, 40)
        }
        .background(bg)
        .task(id: reloadToken) { rows = await emby.loadHome(); loading = false }
    }
}

struct Hero: View {
    @EnvironmentObject var emby: Emby
    let items: [Item]
    @State private var index = 0

    func meta(_ item: Item) -> [String] {
        var m: [String] = []
        if let y = item.ProductionYear { m.append(String(y)) }
        if let t = item.RunTimeTicks, t > 0 { m.append(runtimeText(t)) }
        if let g = item.Genres?.first { m.append(g) }
        return m
    }

    var body: some View {
        let item = items[index % items.count]
        ZStack(alignment: .bottomLeading) {
            Backdrop(id: item.backdropId ?? item.Id).frame(height: 440).frame(maxWidth: .infinity).clipped()
                .id("b" + item.id).transition(.opacity)
            VStack(alignment: .leading, spacing: 14) {
                Text(item.heroTitle).font(.system(size: 52, weight: .black)).lineLimit(2)
                if item.SeriesName != nil {
                    Text("S\(item.ParentIndexNumber ?? 0)·E\(item.IndexNumber ?? 0)  \(item.Name)")
                        .font(.headline).foregroundColor(.white.opacity(0.8))
                }
                HStack(spacing: 12) {
                    ForEach(meta(item), id: \.self) { Text($0) }
                    if let r = item.CommunityRating {
                        HStack(spacing: 3) { Image(systemName: "star.fill"); Text(String(format: "%.1f", r)) }
                            .foregroundColor(.yellow)
                    }
                }.font(.subheadline).foregroundColor(.white.opacity(0.85))
                Text(item.Overview ?? "").font(.body).lineLimit(3).frame(maxWidth: 620, alignment: .leading)
                    .foregroundColor(.white.opacity(0.9))
                HStack(spacing: 12) {
                    Button { Task { await emby.play(item) } } label: {
                        Label("Play", systemImage: "play.fill").font(.system(size: 16, weight: .bold))
                            .padding(.horizontal, 26).frame(height: 44)
                            .background(.white).foregroundColor(.black).cornerRadius(6)
                    }.buttonStyle(.plain)
                    NavigationLink(value: item) {
                        Label("More Info", systemImage: "info.circle").font(.system(size: 16, weight: .bold))
                            .padding(.horizontal, 22).frame(height: 44)
                            .background(Color.gray.opacity(0.55)).foregroundColor(.white).cornerRadius(6)
                    }.buttonStyle(.plain)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(items.indices, id: \.self) { i in
                            let on = i == index % items.count
                            Capsule().fill(on ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.4)))
                                .frame(width: on ? 22 : 8, height: 4)
                                .contentShape(Rectangle().inset(by: -6))
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.8)) { index = i } }
                        }
                    }
                }
            }
            .padding(.horizontal, 44).padding(.vertical, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.55))
            .id("t" + item.id).transition(.opacity)
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 32)
        .foregroundColor(.white)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 1.0)) { index += 1 }
            }
        }
    }
}

/// Landscape card for the Continue Watching row: still image, accent progress bar, time left.
struct ResumeCard: View {
    @EnvironmentObject var emby: Emby
    let item: Item
    @State private var hover = false

    var progress: Double { min(1, max(0, (item.UserData?.PlayedPercentage ?? 0) / 100)) }
    var timeLeft: String? {
        guard let total = item.RunTimeTicks, total > 0 else { return nil }
        let left = max(0, total - (item.UserData?.PlaybackPositionTicks ?? 0))
        return runtimeText(left) + " left"
    }
    var subtitle: String? {
        if item.isEpisode { return "S\(item.ParentIndexNumber ?? 0)·E\(item.IndexNumber ?? 0)" + (timeLeft.map { " · " + $0 } ?? "") }
        return timeLeft
    }
    /// Episodes have a landscape primary image; movies use their backdrop.
    var imageURL: URL? {
        item.isEpisode ? emby.image(item.Id, width: 520) : emby.image(item.backdropId ?? item.Id, "Backdrop", width: 520)
    }

    var body: some View {
        Button { Task { await emby.play(item) } } label: {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: imageURL) { p in
                    p.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack { Color(white: 0.15); Text(item.heroTitle).font(.caption).padding(6) }
                }
                .frame(width: 260, height: 146).clipped()
                .overlay(alignment: .bottom) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.25))
                            Rectangle().fill(.tint).frame(width: g.size.width * progress)
                        }
                    }.frame(height: 4)
                }
                .overlay {
                    if hover {
                        Image(systemName: "play.circle.fill").font(.system(size: 40)).foregroundColor(.white)
                            .shadow(radius: 6)
                    }
                }
                .cornerRadius(8)
                Text(item.heroTitle).font(.callout.weight(.semibold)).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1) }
            }
            .frame(width: 260, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .help(item.isEpisode ? "\(item.heroTitle) — \(item.Name)" : item.Name)
        }.buttonStyle(.plain)
    }
}

struct Backdrop: View {
    @EnvironmentObject var emby: Emby
    let id: String
    var body: some View {
        AsyncImage(url: emby.image(id, "Backdrop", width: 1600)) { p in
            p.resizable().aspectRatio(contentMode: .fill)
        } placeholder: { Color(white: 0.1) }
    }
}

struct PosterCard: View {
    @EnvironmentObject var emby: Emby
    let item: Item
    @State private var hover = false
    var body: some View {
        let played = emby.isPlayed(item)
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: emby.image(item.posterId, width: 360)) { p in
                        p.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack { Color(white: 0.15); Text(item.Name).font(.caption).padding(6) }
                    }
                    .frame(width: 150, height: 225).clipped()
                    .opacity(played ? 0.6 : 1)
                    WatchBadge(item: item, played: played).padding(8)
                }
                .overlay(alignment: .topLeading) {
                    if emby.isFav(item) {
                        Image(systemName: "heart.fill").font(.system(size: 14)).foregroundStyle(.tint)
                            .shadow(color: .black.opacity(0.6), radius: 3).padding(8)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let pct = item.UserData?.PlayedPercentage, pct > 0, pct < 100, !played {
                        ProgressView(value: pct / 100).padding(.horizontal, 8).padding(.bottom, 8)
                    }
                }
                .cornerRadius(8)
                .scaleEffect(hover ? 1.06 : 1).shadow(radius: hover ? 12 : 0)
                .animation(.easeOut(duration: 0.15), value: hover)
                Text(item.Name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(item.ProductionYear.map { String($0) } ?? " ").font(.caption).foregroundColor(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .zIndex(hover ? 1 : 0)
            .help(item.Name)
        }.buttonStyle(.plain)
    }
}

/// One row in the library list view: poster, title, year, overview and watched badge.
struct ListRow: View {
    @EnvironmentObject var emby: Emby
    let item: Item
    @State private var hover = false
    var body: some View {
        let played = emby.isPlayed(item)
        NavigationLink(value: item) {
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: emby.image(item.posterId, width: 160)) { p in
                    p.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color(white: 0.15) }
                .frame(width: 60, height: 90).clipped().cornerRadius(4)
                .opacity(played ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.Name).font(.headline).lineLimit(1)
                    if let y = item.ProductionYear { Text(String(y)).font(.subheadline).foregroundColor(.secondary) }
                    Text(item.Overview ?? "").font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                Spacer(minLength: 12)
                WatchBadge(item: item, played: played)
            }
            .padding(8)
            .background(Color.white.opacity(hover ? 0.08 : 0.03)).cornerRadius(6)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
        }.buttonStyle(.plain)
    }
}

/// "‹ Back" pill button used on detail pages and in the player.
struct BackPill: View {
    var compact = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 6 : 8) {
                Image(systemName: "chevron.left").font(.system(size: compact ? 14 : 18, weight: .bold))
                Text("Back").font(.system(size: compact ? 14 : 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 5 : 10)
            .background(Capsule().fill(Color.black.opacity(hover ? 0.85 : 0.6)))
            .overlay(Capsule().stroke(Color.white.opacity(hover ? 0.7 : 0.3), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .keyboardShortcut("[", modifiers: .command)
    }
}

/// Green badge: a check when the count is 0, otherwise the number.
struct CountBadge: View {
    let count: Int?
    var body: some View {
        if let n = count {
            if n == 0 {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                    .frame(width: 24, height: 24).background(Circle().fill(WatchBadge.green))
                    .shadow(color: .black.opacity(0.5), radius: 3).help("All watched")
            } else {
                Text(n > 99 ? "99+" : "\(n)").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 6).frame(minWidth: 24, minHeight: 24)
                    .background(Capsule().fill(WatchBadge.green))
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .help("\(n) unwatched episode\(n == 1 ? "" : "s")")
            }
        }
    }
}

/// Top-right poster badge: green check when watched, unwatched-episode count for series.
struct WatchBadge: View {
    let item: Item
    let played: Bool
    static let green = Color(red: 0.36, green: 0.66, blue: 0.33)

    var body: some View {
        if played {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Self.green))
                .shadow(color: .black.opacity(0.5), radius: 3)
                .help("Watched")
        } else if item.isSeries, let n = item.UserData?.UnplayedItemCount, n > 0 {
            Text(n > 99 ? "99+" : "\(n)").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 6).frame(minWidth: 24, minHeight: 24)
                .background(Capsule().fill(Self.green))
                .shadow(color: .black.opacity(0.5), radius: 3)
                .help("\(n) unwatched episode\(n == 1 ? "" : "s")")
        }
    }
}

/// 1:02:03 / 12:34 style time.
func timeString(_ t: Double) -> String {
    let s = Int(max(0, t)), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

/// Horizontal row with ‹ › buttons that page through items that don't fit on screen.
/// The buttons only show when there is more to see in that direction; trackpad scrolling still works.
struct ArrowScrollRow<ID: Hashable, Content: View>: View {
    let ids: [ID]
    let itemWidth: CGFloat
    var spacing: CGFloat = 18
    var inset: CGFloat = 40
    @ViewBuilder let content: (ID) -> Content
    @State private var pos: ID?
    @State private var width: CGFloat = 0
    @State private var finder = ScrollFinder()
    @State private var dragStart: CGFloat?

    /// How many items fit in the visible width.
    var visible: Int { max(1, Int((width - inset * 2 + spacing) / (itemWidth + spacing))) }
    /// Index of the first visible item.
    var index: Int { pos.flatMap { ids.firstIndex(of: $0) } ?? 0 }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index + visible < ids.count }

    var body: some View {
        ScrollViewReader { proxy in
            // No scrollbar: the arrows page the row; trackpad / wheel scrolling still works.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(ids, id: \.self) { id in content(id).id(id) }
                }
                .scrollTargetLayout()
                .padding(.vertical, 8)
                .background(ScrollFinderView(finder: finder))
                // Click-and-drag to scroll with the mouse; a plain click still opens the item.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { g in
                            guard let sv = finder.scrollView else { return }
                            let clip = sv.contentView
                            if dragStart == nil { dragStart = clip.bounds.origin.x }
                            let maxX = max(0, (sv.documentView?.frame.width ?? 0) - clip.bounds.width)
                            let x = min(max(0, dragStart! - g.translation.width), maxX)
                            clip.setBoundsOrigin(NSPoint(x: x, y: clip.bounds.origin.y))
                            sv.reflectScrolledClipView(clip)
                        }
                        .onEnded { _ in dragStart = nil }
                )
            }
            .scrollIndicators(.never)
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .scrollPosition(id: $pos)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { width = g.size.width }
            })
            .overlay(alignment: .leading) {
                if canGoBack { arrow("chevron.left", help: "Previous") { page(-1, proxy) }.padding(.leading, 6) }
            }
            .overlay(alignment: .trailing) {
                if canGoForward { arrow("chevron.right", help: "Next") { page(1, proxy) }.padding(.trailing, 6) }
            }
            .animation(.easeOut(duration: 0.15), value: canGoBack)
            .animation(.easeOut(duration: 0.15), value: canGoForward)
        }
    }

    func page(_ dir: Int, _ proxy: ScrollViewProxy) {
        guard !ids.isEmpty else { return }
        // One item per click, with a smooth slide
        let target = min(max(0, index + dir), max(0, ids.count - visible))
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(ids[target], anchor: .leading) }
        pos = ids[target]
    }

    func arrow(_ icon: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.7)))
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(help)
        .transition(.opacity)
    }
}

/// Finds the NSScrollView behind a SwiftUI ScrollView so the mouse can drag it.
final class ScrollFinder { weak var scrollView: NSScrollView? }

struct ScrollFinderView: NSViewRepresentable {
    let finder: ScrollFinder
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { finder.scrollView = v.enclosingScrollView }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        if finder.scrollView == nil { DispatchQueue.main.async { finder.scrollView = v.enclosingScrollView } }
    }
}

// MARK: - Library page (header, tabs, sort, filter; choices are remembered per library)

struct LibraryView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    let lib: LibPref
    @State private var tab = 0
    @State private var items: [Item] = []
    @State private var total = 0
    @State private var loading = false
    @State private var gen = 0
    @State private var sort: String
    @State private var desc: Bool
    @State private var watch: String
    @State private var genre: String
    @State private var genres: [String] = []
    @State private var letter = ""
    @State private var layout: String

    init(lib: LibPref) {
        self.lib = lib
        let d = UserDefaults.standard.dictionary(forKey: "lf-" + lib.id) ?? [:]
        _sort = State(initialValue: d["sort"] as? String ?? "name")
        _desc = State(initialValue: d["desc"] as? Bool ?? false)
        _watch = State(initialValue: d["watch"] as? String ?? "all")
        _genre = State(initialValue: d["genre"] as? String ?? "")
        _layout = State(initialValue: d["layout"] as? String
                        ?? UserDefaults.standard.string(forKey: "defaultLibraryLayout") ?? "grid")
    }

    var key: String { "\(tab)|\(sort)|\(desc)|\(watch)|\(genre)|\(letter)" }
    var filtered: Bool { watch != "all" || !genre.isEmpty }
    var types: String { (tab == 1 || lib.kind == "boxsets") ? "BoxSet" : "Movie,Series,Video,MusicVideo" }
    var sortLabel: String {
        switch sort {
        case "latest": return "Recently Added"
        case "release": return "Release Date"
        case "top": return "Rating"
        default: return "Name"
        }
    }

    func save() {
        let d: [String: Any] = ["sort": sort, "desc": desc, "watch": watch, "genre": genre, "layout": layout]
        UserDefaults.standard.set(d, forKey: "lf-" + lib.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if tab == 2 { genreGrid } else { grid }
            }.padding(.leading, 40).padding(.trailing, 64).padding(.vertical, 24)
        }
        .background(bg)
        .overlay(alignment: .trailing) { if tab != 2 { alphaBar } }
        .task(id: key) { await load(reset: true) }
        .task { genres = await emby.genres(lib) }
        .onChange(of: sort) { desc = (sort != "name") }
        .onChange(of: "\(sort)|\(desc)|\(watch)|\(genre)|\(layout)") { save() }
    }

    var alphaBar: some View {
        VStack(spacing: 1) {
            ForEach(alphaLetters, id: \.self) { l in
                Button { letter = (letter == l) ? "" : l } label: {
                    Text(l).font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 16)
                        .foregroundStyle(letter == l ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.secondary))
                        .background(letter == l ? Color.white.opacity(0.15) : Color.clear)
                        .clipShape(Circle())
                }.buttonStyle(.plain)
            }
        }.padding(.trailing, 14)
    }

    var header: some View {
        VStack(spacing: 16) {
            ZStack {
                HStack { Text(lib.title).font(.title2.bold()); Spacer() }
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        Button { tab = i } label: {
                            Text(i == 0 ? lib.title : ["", "Collections", "Genres", "Favorites"][i])
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(tab == i ? Color.white.opacity(0.28) : Color.clear)
                                .clipShape(Capsule())
                                .foregroundColor(tab == i ? .white : .secondary)
                        }.buttonStyle(.plain)
                    }
                }.padding(3).background(Color.white.opacity(0.1)).clipShape(Capsule())
            }
            if tab != 2 { controls }
        }
    }

    var controls: some View {
        HStack(spacing: 10) {
            Text("\(total) Items").foregroundColor(.secondary).padding(.trailing, 4)
            Button { Task { if let f = items.first { await emby.play(f) } } } label: {
                Label("Play", systemImage: "play.fill").pill()
            }.buttonStyle(.plain)
            Button { Task { await shuffle() } } label: {
                Label("Shuffle", systemImage: "shuffle").pill()
            }.buttonStyle(.plain)
            Menu {
                Picker("Sort by", selection: $sort) {
                    Text("Recently Added").tag("latest")
                    Text("Name").tag("name")
                    Text("Release Date").tag("release")
                    Text("Rating").tag("top")
                }.pickerStyle(.inline)
                Picker("Order", selection: $desc) {
                    Text("Ascending").tag(false)
                    Text("Descending").tag(true)
                }.pickerStyle(.inline)
            } label: {
                Label(sortLabel, systemImage: desc ? "arrow.down" : "arrow.up").pill()
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Menu {
                Picker("Status", selection: $watch) {
                    Text("All").tag("all")
                    Text("Unwatched").tag("unwatched")
                    Text("Watched").tag("watched")
                }.pickerStyle(.inline)
                Picker("Genre", selection: $genre) {
                    Text("All Genres").tag("")
                    ForEach(genres, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.inline)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle").pill(active: filtered)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            if !genre.isEmpty {
                Button { genre = "" } label: { Label(genre, systemImage: "xmark").pill(active: true) }.buttonStyle(.plain)
            }
            layoutToggle
            Menu {
                Button("Refresh") { Task { await load(reset: true) } }
            } label: { Image(systemName: "ellipsis").pill() }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    var grid: some View {
        VStack(spacing: 20) {
            if layout == "list" {
                LazyVStack(spacing: 6) {
                    ForEach(items) { it in
                        ListRow(item: it).onAppear {
                            if it.id == items.last?.id { Task { await load(reset: false) } }
                        }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                    ForEach(items) { it in
                        PosterCard(item: it).onAppear {
                            if it.id == items.last?.id { Task { await load(reset: false) } }
                        }
                    }
                }
            }
            if loading { Spinner() }
            else if items.isEmpty { Text("Nothing here.").foregroundColor(.secondary).padding(40) }
        }
    }

    var layoutToggle: some View {
        HStack(spacing: 0) {
            ForEach([("grid", "square.grid.2x2"), ("list", "list.bullet")], id: \.0) { m in
                Button { layout = m.0 } label: {
                    Image(systemName: m.1).font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .background(layout == m.0 ? Color.white.opacity(0.28) : Color.clear)
                        .foregroundColor(layout == m.0 ? .white : .secondary)
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(m.0 == "grid" ? "Grid view" : "List view")
            }
        }.padding(3).background(Color.white.opacity(0.1)).clipShape(Capsule())
    }

    var genreGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            ForEach(genres, id: \.self) { g in
                Button { genre = g; tab = 0 } label: {
                    Text(g).font(.headline).frame(maxWidth: .infinity, minHeight: 70)
                        .background(Color.white.opacity(0.1)).cornerRadius(8)
                }.buttonStyle(.plain)
            }
        }
    }

    func fetch(start: Int, limit: Int, sort s: String) async -> ItemList {
        await emby.libraryItems(lib, limit: limit, start: start, sort: s, desc: s == sort ? desc : nil,
                                watch: watch, genre: genre, letter: letter, favorites: tab == 3, types: types)
    }

    func load(reset: Bool) async {
        if !reset && (loading || items.count >= total) { return }
        gen += 1
        let my = gen
        loading = true
        let r = await fetch(start: reset ? 0 : items.count, limit: 100, sort: sort)
        guard my == gen else { return }
        if reset { items = r.Items } else { items += r.Items }
        total = r.TotalRecordCount ?? items.count
        loading = false
    }

    func shuffle() async {
        let r = await fetch(start: 0, limit: 1, sort: "random")
        if let f = r.Items.first { await emby.play(f) }
    }
}

// MARK: - Detail / movie info

struct CastTile: View {
    @EnvironmentObject var emby: Emby
    let p: Full.Person
    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: emby.image(p.Id, width: 240)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack { Color(white: 0.18); Image(systemName: "person.fill").font(.system(size: 30)).foregroundColor(.secondary) }
            }
            .frame(width: 88, height: 88).clipShape(Circle())
            Text(p.Name).font(.caption.weight(.semibold)).lineLimit(1)
            Text(p.Role ?? p.`Type` ?? "").font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }.frame(width: 104).multilineTextAlignment(.center)
    }
}

struct DetailView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    @Environment(\.dismiss) var dismiss
    let item: Item
    @State private var full: Full?
    @State private var kids: [Item] = []
    @State private var seasonItems: [Item] = []
    @State private var epLangs: [(code: String, name: String)] = []
    @AppStorage("episodeSubLang") private var epSubLang = ""
    @AppStorage("episodeLayout") private var epLayout = "list"
    @State private var similar: [Item] = []
    @State private var srcIdx = 0
    @State private var audioIdx = -1
    @State private var subIdx = -1
    @State private var quality = UserDefaults.standard.integer(forKey: "defaultQuality")
    @State private var season: Int? = nil
    @State private var nextEp: Item? = nil

    var sources: [MSource] { full?.MediaSources ?? [] }
    var src: MSource? { sources.indices.contains(srcIdx) ? sources[srcIdx] : nil }
    func streams(_ t: String) -> [MStream] { (src?.MediaStreams ?? []).filter { $0.`Type` == t } }
    var defaultAudio: Int {
        let a = streams("Audio")
        return (a.first(where: { $0.IsDefault == true }) ?? a.first)?.Index ?? -1
    }
    var simple: Bool { item.isSeries || item.isBox }

    /// Pre-selects the preferred subtitle language when "Always load" is on.
    func applyPreferredSub() {
        let d = UserDefaults.standard
        guard d.bool(forKey: "subAlways"), let lang = d.string(forKey: "subLang"), !lang.isEmpty,
              let idx = preferredSub(src?.MediaStreams ?? [], lang: lang) else { return }
        subIdx = idx
    }

    /// `from` nil means resume where it was left off; 0 starts over.
    func playNow(from: Double? = nil) {
        if item.isSeries, let ep = nextEp { playEpisode(ep, from: from); return }
        if simple { Task { await emby.play(item) }; return }
        let audioChanged = audioIdx >= 0 && audioIdx != defaultAudio
        emby.playing = PlayRequest(item: item, sourceId: src?.Id,
                                   audio: audioChanged ? audioIdx : nil,
                                   sub: subIdx >= 0 ? subIdx : nil,
                                   maxBitrate: quality > 0 ? quality : nil,
                                   start: from ?? emby.resumeAt(item),
                                   noSub: subIdx < 0)
    }

    /// The item the big Play button acts on (next-up episode for a series).
    var playTarget: Item? { item.isSeries ? nextEp : (simple ? nil : item) }

    var playLabel: String {
        let r = playTarget.map { emby.resumeAt($0) } ?? 0
        let verb = r > 0 ? "Resume" : "Play"
        if item.isSeries, let ep = nextEp { return "\(verb) S\(ep.ParentIndexNumber ?? 0):E\(ep.IndexNumber ?? 0)" }
        if r > 0 { return "Resume from \(timeString(r))" }
        return verb
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                if item.isSeries { episodesList }
                if item.isBox { boxGrid }
                castSection
                aboutSection
                similarSection
            }.padding(.bottom, 50)
        }
        .background(alignment: .top) {
            ZStack {
                Backdrop(id: item.backdropId ?? item.Id).frame(height: 520).clipped().opacity(0.35)
                LinearGradient(colors: [Color.clear, bg], startPoint: .top, endPoint: .bottom)
            }.frame(height: 520)
        }
        .background(bg)
        .task {
            full = await emby.full(item.id)
            audioIdx = defaultAudio
            applyPreferredSub()
            if item.isSeries {
                async let eps = emby.episodes(item.id)
                async let ss = emby.seasons(item.id)
                kids = await eps; seasonItems = await ss
                nextEp = await emby.nextUp(item.id) ?? kids.first { !emby.isPlayed($0) } ?? kids.first
                if let first = kids.first { epLangs = Self.subLangs(await emby.full(first.id)) }
            }
            else if item.isBox { kids = await emby.children(item.id) }
            if !item.isEpisode { similar = await emby.similar(item.id) }
        }
        .onChange(of: srcIdx) { audioIdx = defaultAudio; subIdx = -1; applyPreferredSub() }
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .navigation) { BackPill(compact: true) { dismiss() } } }
    }

    // Header: poster + info + pickers + buttons
    var header: some View {
        HStack(alignment: .top, spacing: 28) {
            AsyncImage(url: emby.image(item.id, width: 500)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { ZStack { Color(white: 0.15); Text(item.Name).padding() } }
            .frame(width: item.isEpisode ? 320 : 220, height: item.isEpisode ? 180 : 330)
            .clipped().cornerRadius(10).shadow(color: .black.opacity(0.5), radius: 16, y: 8)
            VStack(alignment: .leading, spacing: 14) {
                Text(item.Name).font(.system(size: 46, weight: .black))
                meta
                if !simple { streamsRow }
                buttons
                if let tag = full?.Taglines?.first { Text(tag).font(.headline) }
                Text(item.Overview ?? "").frame(maxWidth: 760, alignment: .leading)
                let directors = (full?.People ?? []).filter { $0.`Type` == "Director" }.map { $0.Name }
                if !directors.isEmpty {
                    (Text("Director: ").foregroundColor(.secondary) + Text(directors.joined(separator: ", ")).bold())
                        .font(.callout)
                }
            }
        }.padding(.horizontal, 40).padding(.top, 40)
    }

    var meta: some View {
        HStack(spacing: 12) {
            if let r = full?.CommunityRating {
                HStack(spacing: 3) { Image(systemName: "star.fill").foregroundColor(.yellow); Text(String(format: "%.1f", r)) }
            }
            if let c = full?.CriticRating { Text("🍅 \(Int(c))%") }
            if let y = item.ProductionYear { Text(String(y)) }
            if let t = full?.RunTimeTicks { Text(runtimeText(t)) }
            if let o = full?.OfficialRating {
                Text(o).font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary))
            }
            if let g = full?.Genres?.first { Text(g) }
            if let t = full?.RunTimeTicks, !simple { Text("Ends at " + endsAtText(t)) }
        }.font(.subheadline).foregroundColor(.secondary)
    }

    var streamsRow: some View {
        HStack(spacing: 20) {
            if sources.count > 1 {
                labeled("Version") {
                    Picker("", selection: $srcIdx) {
                        ForEach(sources.indices, id: \.self) { Text(sources[$0].Name ?? sources[$0].Path ?? "Version \($0 + 1)").tag($0) }
                    }
                }
            }
            if let v = streams("Video").first {
                HStack(spacing: 6) { Text("Video").foregroundColor(.secondary); Text(v.DisplayTitle ?? "") }
            }
            if !streams("Audio").isEmpty {
                labeled("Audio") {
                    Picker("", selection: $audioIdx) {
                        ForEach(streams("Audio")) { Text($0.DisplayTitle ?? "Track \($0.Index)").tag($0.Index) }
                    }
                }
            }
            labeled("Subtitles") {
                Picker("", selection: $subIdx) {
                    Text("Off").tag(-1)
                    ForEach(streams("Subtitle")) { Text($0.DisplayTitle ?? "Track \($0.Index)").tag($0.Index) }
                }
            }
            labeled("Quality") {
                Picker("", selection: $quality) {
                    Text("Original").tag(0)
                    Text("1080p · 8 Mbps").tag(8_000_000)
                    Text("720p · 4 Mbps").tag(4_000_000)
                    Text("480p · 1.5 Mbps").tag(1_500_000)
                }
            }
        }.font(.callout)
    }

    func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundColor(.secondary)
            content().pickerStyle(.menu).labelsHidden().fixedSize()
        }
    }

    var buttons: some View {
        let played = emby.isPlayed(item)
        return HStack(spacing: 10) {
            Button { playNow() } label: {
                Label(playLabel, systemImage: "play.fill").bold()
                    .padding(.horizontal, 24).frame(height: 44)
                    .background(.white).foregroundColor(.black).clipShape(Capsule())
            }.buttonStyle(.plain)
            if let t = playTarget, emby.resumeAt(t) > 0 {
                Button { playNow(from: 0) } label: { Label("Start Over", systemImage: "arrow.counterclockwise").pill() }
                    .buttonStyle(.plain)
            }
            if let t = full?.RemoteTrailers?.first?.Url, let u = URL(string: t) {
                Button { NSWorkspace.shared.open(u) } label: { Label("Trailer", systemImage: "film").pill() }.buttonStyle(.plain)
            }
            Button { Task { await emby.setPlayed(item.id, !played) } } label: {
                if played { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).circleButton() }
                else { Image(systemName: "checkmark.circle").circleButton() }
            }.buttonStyle(.plain).help(played ? "Mark as unwatched" : "Mark as watched")
            Button { Task { await emby.setFav(item.id, !emby.isFav(item)) } } label: {
                if emby.isFav(item) { Image(systemName: "heart.fill").foregroundStyle(.tint).circleButton() }
                else { Image(systemName: "heart").circleButton() }
            }.buttonStyle(.plain).help("Favorite")
        }
    }

    /// Language name from "English (SRT)" etc., so "eng" and "en" tracks group together.
    static func langName(_ st: MStream) -> String {
        let t = st.DisplayTitle ?? st.Language ?? "Unknown"
        return t.components(separatedBy: " (").first ?? t
    }

    /// Subtitle languages found in an item, keyed by language code.
    static func subLangs(_ f: Full?) -> [(code: String, name: String)] {
        var out: [(code: String, name: String)] = []
        for st in f?.MediaSources?.first?.MediaStreams ?? [] where st.`Type` == "Subtitle" {
            let name = langName(st)
            if out.contains(where: { $0.code == name.lowercased() }) { continue }
            out.append((name.lowercased(), name))
        }
        return out
    }

    /// Plays an episode with the subtitle language chosen for episodes (text formats like SRT preferred).
    /// Plays an episode; `from` nil means resume where it was left off.
    func playEpisode(_ ep: Item, from: Double? = nil) {
        let q = UserDefaults.standard.integer(forKey: "defaultQuality")
        let maxBitrate: Int? = q > 0 ? q : nil
        let start: Double = from ?? emby.resumeAt(ep)
        if epSubLang.isEmpty { emby.playing = PlayRequest(item: ep, maxBitrate: maxBitrate, start: start); return }
        Task {
            let f = await emby.full(ep.id)
            let src = f?.MediaSources?.first
            let subs = (src?.MediaStreams ?? []).filter {
                $0.`Type` == "Subtitle" && Self.langName($0).lowercased() == epSubLang }
            let text = ["srt", "subrip", "vtt", "ass", "ssa"]
            let pick = subs.first { text.contains(($0.Codec ?? "").lowercased()) } ?? subs.first
            emby.playing = PlayRequest(item: ep, sourceId: src?.Id, sub: pick?.Index, maxBitrate: maxBitrate, start: start)
        }
    }

    var seasonNumbers: [Int] {
        let set = Set(kids.map { $0.ParentIndexNumber ?? 0 })
        return set.sorted { (a: Int, b: Int) -> Bool in
            if a == 0 { return false }
            if b == 0 { return true }
            return a < b
        }
    }

    var currentSeason: Int {
        if let season { return season }
        if let firstUnwatched = kids.first(where: { !emby.isPlayed($0) })?.ParentIndexNumber { return firstUnwatched }
        return seasonNumbers.first ?? 0
    }

    func seasonTitle(_ n: Int) -> String {
        if n == 0 { return "Specials" }
        return seasonItems.first { ($0.IndexNumber ?? 0) == n }?.Name ?? "Season \(n)"
    }

    /// Unwatched episodes in a season (nil while episodes are loading).
    func unwatched(_ n: Int) -> Int? {
        let eps = kids.filter { ($0.ParentIndexNumber ?? 0) == n }
        return eps.isEmpty ? nil : eps.filter { !emby.isPlayed($0) }.count
    }

    func seasonPoster(_ n: Int) -> some View {
        let sItem: Item? = seasonItems.first { ($0.IndexNumber ?? 0) == n }
        let title: String = seasonTitle(n)
        let selected: Bool = n == currentSeason
        return Button { season = n } label: {
            VStack(spacing: 8) {
                AsyncImage(url: emby.image(sItem?.Id ?? item.Id, width: 400)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack { Color(white: 0.15); Text(title) }
                }
                .frame(width: 170, height: 255).clipped().cornerRadius(8)
                .overlay(alignment: .topTrailing) { CountBadge(count: unwatched(n)).padding(8) }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: selected ? 3 : 0))
                .shadow(radius: 6)
                Text(title).font(.body).foregroundColor(selected ? .primary : .secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var seasonRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons").font(.title3.bold()).padding(.horizontal, 40)
            ArrowScrollRow(ids: seasonNumbers, itemWidth: 170) { n in seasonPoster(n) }
        }
    }

    var episodesHeader: some View {
        let multi: Bool = seasonNumbers.count > 1
        let heading: String = multi ? seasonTitle(currentSeason) : "Episodes"
        return HStack(spacing: 16) {
            Text(heading).font(.title3.bold())
            Spacer()
            episodeLayoutToggle
            if !epLangs.isEmpty {
                Text("Subtitles").foregroundColor(.secondary)
                Picker("", selection: $epSubLang) {
                    Text("Off").tag("")
                    ForEach(epLangs, id: \.code) { l in Text(l.name).tag(l.code) }
                }.labelsHidden().fixedSize()
            }
        }.padding(.horizontal, 40).padding(.top, 10)
    }

    func episodeRow(_ ep: Item) -> some View {
        let played: Bool = emby.isPlayed(ep)
        let label: String = "S\(ep.ParentIndexNumber ?? 0)·E\(ep.IndexNumber ?? 0)  \(ep.Name)"
        return Button { playEpisode(ep) } label: {
            HStack(spacing: 14) {
                AsyncImage(url: emby.image(ep.id, width: 320)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color(white: 0.15) }
                .frame(width: 160, height: 90).clipped().cornerRadius(4)
                .opacity(played ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).bold()
                    Text(ep.Overview ?? "").lineLimit(2).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                WatchBadge(item: ep, played: played)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 40)
        .contextMenu {
            Button("Play from Beginning") { playEpisode(ep, from: 0) }
            Button(played ? "Mark as unwatched" : "Mark as watched") {
                Task { await emby.setPlayed(ep.id, !played) }
            }
        }
    }

    var episodesList: some View {
        let cur: Int = currentSeason
        let eps: [Item] = kids.filter { ($0.ParentIndexNumber ?? 0) == cur }
        return VStack(alignment: .leading, spacing: 12) {
            if seasonNumbers.count > 1 { seasonRow }
            episodesHeader
            if epLayout == "grid" {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 22) {
                    ForEach(eps) { ep in episodeTile(ep) }
                }.padding(.horizontal, 40)
            } else {
                ForEach(eps) { ep in episodeRow(ep) }
            }
        }
    }

    var episodeLayoutToggle: some View {
        HStack(spacing: 0) {
            ForEach([("grid", "square.grid.2x2"), ("list", "list.bullet")], id: \.0) { m in
                Button { epLayout = m.0 } label: {
                    Image(systemName: m.1).font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .background(epLayout == m.0 ? Color.white.opacity(0.28) : Color.clear)
                        .foregroundColor(epLayout == m.0 ? .white : .secondary)
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(m.0 == "grid" ? "Grid view" : "List view")
            }
        }.padding(3).background(Color.white.opacity(0.1)).clipShape(Capsule())
    }

    func episodeTile(_ ep: Item) -> some View {
        let played: Bool = emby.isPlayed(ep)
        let label: String = "\(ep.IndexNumber ?? 0). \(ep.Name)"
        return Button { playEpisode(ep) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: emby.image(ep.id, width: 520)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color(white: 0.15) }
                    .frame(minWidth: 0, maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
                    .clipped().cornerRadius(6)
                    .opacity(played ? 0.6 : 1)
                    WatchBadge(item: ep, played: played).padding(6)
                }
                .overlay(alignment: .bottom) {
                    if let pct = ep.UserData?.PlayedPercentage, pct > 0, pct < 100, !played {
                        ProgressView(value: pct / 100).padding(.horizontal, 8).padding(.bottom, 6)
                    }
                }
                Text(label).font(.headline).lineLimit(1)
                Text(ep.Overview ?? "").font(.caption).foregroundColor(.secondary).lineLimit(2)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play from Beginning") { playEpisode(ep, from: 0) }
            Button(played ? "Mark as unwatched" : "Mark as watched") {
                Task { await emby.setPlayed(ep.id, !played) }
            }
        }
    }

    var boxGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
            ForEach(kids) { PosterCard(item: $0) }
        }.padding(.horizontal, 40)
    }

    @ViewBuilder var castSection: some View {
        let people = Array((full?.People ?? []).prefix(30))
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cast & Crew").font(.title3.bold()).padding(.horizontal, 40)
                ArrowScrollRow(ids: Array(people.indices), itemWidth: 104) { i in
                    NavigationLink(value: PersonRef(id: people[i].Id, name: people[i].Name)) { CastTile(p: people[i]) }
                        .buttonStyle(.plain).help("Show everything with \(people[i].Name)")
                }
            }
        }
    }

    func mediaInfo(_ s: MSource, _ f: Full) -> String {
        var info = (s.Container ?? "").uppercased()
        if let z = s.Size { info += "  " + ByteCountFormatter.string(fromByteCount: z, countStyle: .file) }
        if let a = parseDate(f.DateCreated) { info += "  Added " + a.formatted(date: .abbreviated, time: .shortened) }
        return info
    }

    func aboutRow(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).bold()
            Text(text).foregroundColor(.secondary).textSelection(.enabled)
        }
    }

    @ViewBuilder var aboutSection: some View {
        if let f = full {
            VStack(alignment: .leading, spacing: 16) {
                Text("About").font(.title3.bold())
                if let d = parseDate(f.UserData?.LastPlayedDate) {
                    aboutRow("Date Last Played", d.formatted(date: .abbreviated, time: .shortened))
                }
                if let g = f.Genres, !g.isEmpty { aboutRow("Genres", g.joined(separator: ", ")) }
                if let s = f.Studios, !s.isEmpty { aboutRow("Studios", s.map { $0.Name }.joined(separator: ", ")) }
                if let links = f.ExternalUrls, !links.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Links").bold()
                        HStack(spacing: 10) {
                            ForEach(links.indices, id: \.self) { i in
                                if let n = links[i].Name, let u = links[i].Url.flatMap({ URL(string: $0) }) { Link(n, destination: u) }
                            }
                        }
                    }
                }
                if let s = src {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Media Info").bold()
                        if let p = s.Path { Text(p).foregroundColor(.secondary).textSelection(.enabled) }
                        Text(mediaInfo(s, f)).foregroundColor(.secondary)
                    }
                }
            }.padding(.horizontal, 40).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder var similarSection: some View {
        if !similar.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("More Like This").font(.title3.bold()).padding(.horizontal, 40)
                ArrowScrollRow(ids: Array(similar.indices), itemWidth: 150, spacing: 14) { PosterCard(item: similar[$0]) }
            }
        }
    }
}

// MARK: - Player (inside the main window)

@MainActor
final class PlayerModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var error = ""
    @Published var caption = ""
    @Published var loadingSubs = false
    private var subGen = 0
    // Current state shown in the player menus
    @Published var streams: [MStream] = []
    @Published var sub: Int? = nil
    @Published var audio: Int? = nil
    @Published var quality = 0
    @Published var speed: Float = {
        let v = UserDefaults.standard.double(forKey: "defaultSpeed")
        return v > 0 ? Float(v) : 1
    }()
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var volume: Float = 1 { didSet { player?.volume = volume } }
    @Published var subOffset = 0 { didSet { updateCaption(now) } }   // ms, positive = later
    private var obs: NSKeyValueObservation?
    private var cues: [Cue] = []
    private var timeObs: Any?
    private var req: PlayRequest?
    private var pendingSeek: Double = 0
    private weak var emby: Emby?
    private var lastReport: Double = 0
    private var reportedStart = false
    private var session: Emby.PlaySession?

    // Chapters, intro/credits markers, scrub thumbnails, picture-in-picture
    @Published var chapters: [Chapter] = []
    @Published var hasThumbs = false
    @Published var inIntro = false            // shown as a "Skip Intro" button when auto-skip is off
    @Published var skippedIntro = false       // brief "Intro skipped" notice
    @Published var pipActive = false
    private var metaFor = ""
    private var introDone = false
    private var bif = Data()
    private var frames: [(t: Double, r: Range<Int>)] = []
    private var thumbCache: [Int: NSImage] = [:]
    private var pip: AVPictureInPictureController?
    private var pipObs: NSKeyValueObservation?

    var introStart: Double? { chapters.first { $0.MarkerType == "IntroStart" }?.start }
    var introEnd: Double? { chapters.first { $0.MarkerType == "IntroEnd" }?.start }
    var creditsStart: Double? { chapters.first { $0.MarkerType == "CreditsStart" }?.start }
    /// Real chapters with their index on the server (needed for chapter images).
    var chapterList: [(i: Int, c: Chapter)] { chapters.enumerated().filter { !$0.element.isMarker }.map { ($0.offset, $0.element) } }
    var isTranscoding: Bool { session?.method == "Transcode" }
    var autoSkipIntro: Bool { UserDefaults.standard.object(forKey: "autoSkipIntro") as? Bool ?? true }

    var audioStreams: [MStream] { streams.filter { $0.`Type` == "Audio" } }
    var subStreams: [MStream] { streams.filter { $0.`Type` == "Subtitle" } }
    var now: Double { player?.currentTime().seconds ?? 0 }

    var watchedEnough: Bool {
        guard let p = player, let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 else { return false }
        return p.currentTime().seconds / d > 0.9
    }

    func start(_ emby: Emby, _ req: PlayRequest, direct: Bool = true) async {
        stop()
        error = ""; cues = []
        self.emby = emby
        if pendingSeek == 0, let s = req.start, s > 0 { pendingSeek = s }
        self.req = req
        sub = req.sub; quality = req.maxBitrate ?? 0
        if streams.isEmpty || metaFor != req.item.id, let f = await emby.full(req.item.id) {
            let src = f.MediaSources?.first { $0.Id == req.sourceId } ?? f.MediaSources?.first
            if streams.isEmpty { streams = src?.MediaStreams ?? [] }
            if metaFor != req.item.id {
                metaFor = req.item.id
                chapters = f.Chapters ?? []
                introDone = false; inIntro = false
                loadThumbs(emby, req.item.id, src?.Id)
            }
        }
        let auds = streams.filter { $0.`Type` == "Audio" }
        audio = req.audio ?? (auds.first { $0.IsDefault == true } ?? auds.first)?.Index
        var req = req
        // Audio / subtitles remembered for this series
        if req.item.isEpisode, let sid = req.item.SeriesId, let m = SeriesLang.get(sid) {
            if req.sub == nil, !req.noSub, let l = m["sub"] {
                if l == "off" { req.noSub = true; self.req?.noSub = true }
                else if let i = preferredSub(streams, lang: l) { req.sub = i; sub = i; self.req?.sub = i }
            }
            if req.audio == nil, let l = m["audio"],
               let st = auds.first(where: { ($0.Language ?? "").lowercased() == l.lowercased() }), st.Index != audio {
                req.audio = st.Index; audio = st.Index; self.req?.audio = st.Index
            }
        }
        // "Always load preferred subtitle language"
        let d = UserDefaults.standard
        if req.sub == nil, !req.noSub, d.bool(forKey: "subAlways"), let lang = d.string(forKey: "subLang"), !lang.isEmpty,
           let idx = preferredSub(streams, lang: lang) {
            req.sub = idx; sub = idx; self.req?.sub = idx
        }
        // Text subtitles are drawn by the app and load in the background, so the video starts right away
        // (embedded ones can take a while the first time). Image subtitles are burned in by the server.
        if let s = req.sub, !isImageSub(s), !req.burnIn {
            req.sub = nil
            loadCues(emby, req.item.id, req.sourceId, s)
        }
        guard let u = await emby.resolveStream(req, direct: direct) else {
            error = "Couldn't get a stream from the server."; return
        }
        let method = u.absoluteString.contains("Static=true") ? "DirectPlay" : "Transcode"
        session = Emby.PlaySession(itemId: req.item.id, sourceId: req.sourceId, method: method, url: u)
        let it = AVPlayerItem(url: u)
        obs = it.observe(\.status, options: [.new]) { [weak self] i, _ in
            if i.status == .failed {
                let m = i.error?.localizedDescription ?? "Playback failed."
                Task { @MainActor in self?.error = m }
            }
            if i.status == .readyToPlay {
                Task { @MainActor in
                    guard let self else { return }
                    if self.pendingSeek > 0 {
                        let t = self.pendingSeek; self.pendingSeek = 0
                        self.time = t
                        await self.player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
                    }
                    if !self.reportedStart, let ps = self.session {
                        self.reportedStart = true
                        await self.emby?.reportStart(ps, self.now)
                    }
                }
            }
        }
        let p = AVPlayer(playerItem: it)
        p.volume = volume
        timeObs = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        player = p
        p.defaultRate = speed
        p.play()
    }

    /// Restart the stream with new settings, keeping the playback position.
    private func restart(_ emby: Emby, _ change: (inout PlayRequest) -> Void) async {
        guard var r = req else { return }
        change(&r)
        pendingSeek = now
        await start(emby, r)
    }

    func isImageSub(_ idx: Int) -> Bool {
        imageSubCodecs.contains((streams.first { $0.Index == idx }?.Codec ?? "").lowercased())
    }

    /// Downloads a text subtitle in the background; playback keeps going meanwhile.
    private func loadCues(_ emby: Emby, _ itemId: String, _ sourceId: String?, _ idx: Int) {
        subGen += 1
        let gen = subGen
        cues = []; caption = ""; loadingSubs = true
        Task {
            let c = await emby.subtitleCues(itemId, sourceId, idx)
            guard gen == subGen else { return }   // user picked another track meanwhile
            loadingSubs = false
            if let c { cues = c; updateCaption(now) }
            else { await restart(emby) { $0.sub = idx; $0.burnIn = true } }   // couldn't read as text: burn it in
        }
    }

    func setSub(_ emby: Emby, _ idx: Int?) async {
        guard idx != sub, let r = req else { return }
        if r.item.isEpisode, let sid = r.item.SeriesId {
            SeriesLang.set(sid, "sub", idx.flatMap { i in streams.first { $0.Index == i } }.map(subLangName) ?? "off")
        }
        let wasBurned = sub.map(isImageSub) ?? false
        if let idx {
            if isImageSub(idx) {
                await restart(emby) { $0.sub = idx }
            } else {
                sub = idx; req?.sub = idx
                if wasBurned { await restart(emby) { $0.sub = idx } }
                else { loadCues(emby, r.item.id, r.sourceId, idx) }
            }
        } else {
            subGen += 1
            cues = []; caption = ""; loadingSubs = false; sub = nil; req?.sub = nil; req?.noSub = true
            if wasBurned { await restart(emby) { $0.sub = nil; $0.noSub = true } }
        }
    }

    func setAudio(_ emby: Emby, _ idx: Int) async {
        guard idx != audio else { return }
        if let r = req, r.item.isEpisode, let sid = r.item.SeriesId,
           let l = streams.first(where: { $0.Index == idx })?.Language, !l.isEmpty {
            SeriesLang.set(sid, "audio", l)
        }
        await restart(emby) { $0.audio = idx }
    }

    func setQuality(_ emby: Emby, _ q: Int) async {
        guard q != quality else { return }
        await restart(emby) { $0.maxBitrate = q > 0 ? q : nil }
    }

    func setSpeed(_ r: Float) {
        speed = r
        player?.defaultRate = r
        if player?.rate ?? 0 > 0 { player?.rate = r }
    }

    private func tick(_ t: Double) {
        if t.isFinite { time = t }
        if let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        let isPlaying = (player?.rate ?? 0) > 0
        if isPlaying != playing {
            playing = isPlaying
            sendProgress(t, force: true)
        }
        sendProgress(t)
        updateCaption(t)
        checkIntro(t)
    }

    private func checkIntro(_ t: Double) {
        guard let s = introStart, let e = introEnd, e > s + 2, t.isFinite else { return }
        let inside = t >= s && t < e - 1
        if inside, !introDone, autoSkipIntro {
            introDone = true
            seek(to: e)
            skippedIntro = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                self.skippedIntro = false
            }
            return
        }
        if inside != inIntro { inIntro = inside && !autoSkipIntro }
    }

    func skipIntro() { if let e = introEnd { introDone = true; inIntro = false; seek(to: e) } }
    func watchIntro() { if let s = introStart { skippedIntro = false; seek(to: s) } }

    // MARK: Scrub thumbnails (BIF)

    private func loadThumbs(_ emby: Emby, _ id: String, _ sourceId: String?) {
        bif = Data(); frames = []; thumbCache = [:]; hasThumbs = false
        Task { @MainActor in
            guard let d = await emby.bifData(id, sourceId), self.metaFor == id else { return }
            let f = Self.parseBIF(d)
            self.bif = d; self.frames = f; self.hasThumbs = !f.isEmpty
        }
    }

    /// BIF: 64-byte header (magic, version, count @12, ms per frame @16), then (frame, offset) pairs.
    static func parseBIF(_ d: Data) -> [(t: Double, r: Range<Int>)] {
        let magic: [UInt8] = [0x89, 0x42, 0x49, 0x46]
        guard d.count > 72, Array(d.prefix(4)) == magic else { return [] }
        func u32(_ o: Int) -> Int {
            guard o + 4 <= d.count else { return 0 }
            return d.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }
        }
        let count = u32(12)
        let sep = Double(u32(16) == 0 ? 1000 : u32(16)) / 1000
        var out: [(t: Double, r: Range<Int>)] = []
        guard count > 0, 64 + 8 * (count + 1) <= d.count else { return [] }
        for i in 0..<count {
            let ts = u32(64 + 8 * i), a = u32(64 + 8 * i + 4), b = u32(64 + 8 * (i + 1) + 4)
            if ts == 0xFFFF_FFFF { break }
            if a < b, b <= d.count { out.append((Double(ts) * sep, a..<b)) }
        }
        return out
    }

    func thumb(at t: Double) -> NSImage? {
        guard !frames.isEmpty else { return nil }
        var lo = 0, hi = frames.count - 1, f = 0
        while lo <= hi {
            let m = (lo + hi) / 2
            if frames[m].t <= t { f = m; lo = m + 1 } else { hi = m - 1 }
        }
        if let img = thumbCache[f] { return img }
        let img = NSImage(data: bif.subdata(in: frames[f].r))
        if thumbCache.count > 200 { thumbCache.removeAll() }
        thumbCache[f] = img
        return img
    }

    // MARK: Picture in picture

    var pipSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func attach(_ layer: AVPlayerLayer) {
        guard pipSupported, pip?.playerLayer !== layer else { return }
        pip = AVPictureInPictureController(playerLayer: layer)
        pipObs = pip?.observe(\.isPictureInPictureActive, options: [.new]) { [weak self] c, _ in
            let on = c.isPictureInPictureActive
            Task { @MainActor in self?.pipActive = on }
        }
    }

    func togglePiP() {
        guard let p = pip else { return }
        if p.isPictureInPictureActive { p.stopPictureInPicture() } else { p.startPictureInPicture() }
    }

    // MARK: Playback info

    func playbackInfo() async -> [(String, String)] {
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        func mbps(_ b: Double) -> String { b >= 1_000_000 ? String(format: "%.1f Mbps", b / 1_000_000) : "\(Int(b / 1000)) kbps" }
        var out: [(String, String)] = []
        out.append(("Play method", isTranscoding ? "Transcode" : "Direct play"))
        if let v = streams.first(where: { $0.`Type` == "Video" }) {
            var s = (v.Codec ?? "?").uppercased()
            if let w = v.Width, let h = v.Height { s += " · \(w)×\(h)" }
            if let b = v.BitRate { s += " · " + mbps(Double(b)) }
            out.append(("Source video", s))
        }
        if let a = streams.first(where: { $0.Index == audio }) { out.append(("Source audio", a.DisplayTitle ?? a.Codec ?? "?")) }
        if isTranscoding, let t = await emby?.sessionInfo()?["TranscodingInfo"] as? [String: Any] {
            var v = (t["IsVideoDirect"] as? Bool == true) ? "copied" : ((t["VideoCodec"] as? String ?? "?").uppercased())
            if let w = num(t["Width"]), let h = num(t["Height"]) { v += " · \(Int(w))×\(Int(h))" }
            out.append(("Server video", v))
            out.append(("Server audio", (t["IsAudioDirect"] as? Bool == true) ? "copied" : ((t["AudioCodec"] as? String ?? "?").uppercased())))
            if let b = num(t["Bitrate"]) { out.append(("Stream bitrate", mbps(b))) }
            if let f = num(t["Framerate"]) { out.append(("Encoder speed", String(format: "%.0f fps", f))) }
            if let r = t["TranscodeReasons"] as? [String], !r.isEmpty {
                out.append(("Why transcoding", r.map { $0.replacingOccurrences(of: "NotSupported", with: " not supported") }.joined(separator: ", ")))
            }
        }
        if let it = player?.currentItem {
            let sz = it.presentationSize
            if sz.width > 0 { out.append(("Playing", "\(Int(sz.width))×\(Int(sz.height))")) }
            if let e = it.accessLog()?.events.last {
                if e.indicatedBitrate > 0 { out.append(("Indicated", mbps(e.indicatedBitrate))) }
                if e.observedBitrate > 0 { out.append(("Network", mbps(e.observedBitrate))) }
                out.append(("Dropped / stalls", "\(max(0, e.numberOfDroppedVideoFrames)) / \(max(0, e.numberOfStalls))"))
            }
        }
        return out
    }

    /// Tells the server the current position every 10 s (and on pause/play), so it can resume later.
    private func sendProgress(_ t: Double, force: Bool = false) {
        guard reportedStart, let ps = session, t.isFinite, force || abs(t - lastReport) >= 10 else { return }
        lastReport = t
        let paused = !playing
        Task { await emby?.reportProgress(ps, t, paused: paused) }
    }

    private var pausedAt: Date?
    private var debugTimer: Timer?

    func togglePlay() {
        guard let p = player else { return }
        if p.rate > 0 {
            p.pause(); pausedAt = Date()
            dlog("pause at \(fmt(now))")
            startDebugPolling()
        } else {
            let away = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
            pausedAt = nil
            debugTimer?.invalidate(); debugTimer = nil
            dlog("resume at \(fmt(now)) after \(Int(away))s pause")
            // After a long pause the server may have stopped/restarted its transcode, shifting the
            // stream's timeline. Re-seeking makes the player fetch fresh segments and realign its clock.
            if away > 30, session?.method == "Transcode" {
                let t = now
                dlog("realign: re-seek to \(fmt(t))")
                p.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor in self?.dlog("realigned, player at \(self?.fmt(self?.now ?? 0) ?? "")"); self?.logServer() }
                }
            }
            p.play()
        }
        playing = p.rate > 0
    }

    // MARK: debug log (~/Library/Logs/EmbyFlix.log)
    private func fmt(_ t: Double) -> String { String(format: "%.2fs", t) }
    private func startDebugPolling() {
        logServer()
        debugTimer?.invalidate()
        debugTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.logServer() }
        }
    }
    private func logServer() {
        guard let e = emby else { return }
        let t = now, ev = player?.currentItem?.accessLog()?.events.last
        Task { @MainActor in
            let s = await e.mySessionJSON()
            self.dlog("player \(self.fmt(t)) segs=\(ev?.numberOfMediaRequests ?? 0) stalls=\(ev?.numberOfStalls ?? 0) | server \(s)")
        }
    }
    func dlog(_ m: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(m)\n"
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/EmbyFlix.log")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: u) }
    }

    func seek(to t: Double) {
        let c = max(0, duration > 0 ? min(t, duration - 1) : t)
        time = c
        player?.seek(to: CMTime(seconds: c, preferredTimescale: 600))
        updateCaption(c)
    }

    func skip(_ d: Double) { seek(to: now + d) }

    private func updateCaption(_ raw: Double) {
        let t = raw - Double(subOffset) / 1000
        // binary search for the last cue starting at or before t
        var lo = 0, hi = cues.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= t { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        let text = found >= 0 && t <= cues[found].end ? cues[found].text : ""
        if text != caption { caption = text }
    }

    func stop() {
        if let p = player, let ps = session, reportedStart {
            let t = p.currentTime().seconds
            let d = p.currentItem?.duration.seconds ?? 0
            let e = emby
            Task { await e?.reportStopped(ps, t.isFinite ? t : 0, duration: d.isFinite ? d : 0) }
        } else if let ps = session, let e = emby {
            Task { await e.stopEncoding(ps) }   // closed before playback began: still kill the transcode
        }
        session = nil
        reportedStart = false; lastReport = 0
        if let o = timeObs { player?.removeTimeObserver(o) }
        timeObs = nil
        debugTimer?.invalidate(); debugTimer = nil; pausedAt = nil
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        player?.pause(); player = nil; obs = nil; caption = ""
    }
}

struct PlayerView: View {
    @EnvironmentObject var emby: Emby
    @StateObject private var model = PlayerModel()
    let req: PlayRequest

    enum Panel { case subtitles, appearance, chapters }
    @State private var panel: Panel?
    @State private var showUI = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrub: Double = 0
    @State private var episodes: [Item] = []
    @FocusState private var focused: Bool
    @State private var showInfo = false
    @State private var infoLines: [(String, String)] = []
    @State private var hoverX: CGFloat?
    @State private var sliderW: CGFloat = 1
    @State private var upNextCancelled = false
    @State private var upNextLeft = 10

    // Subtitle appearance (defaults: normal size, white, drop shadow, transparent, 10% from bottom)
    @AppStorage("subTextSize") private var subTextSize = "normal"
    @AppStorage("subColor") private var subColor = "white"
    @AppStorage("subShadowStyle") private var subShadow = "drop"
    @AppStorage("subBg") private var subBg = "none"
    @AppStorage("subBottom") private var subBottom = 10.0
    @AppStorage("skipSeconds") private var skipSecs = 10
    @AppStorage("autoNext") private var autoNext = true
    @AppStorage("clickToPause") private var clickToPause = true
    @AppStorage("accent") private var accentName = "red"
    var accent: Color { Theme.accent(accentName) }
    @State private var isFullScreen = false
    @State private var enteredFullScreen = false

    static let sizes: [(String, String, Double)] = [("smaller", "Smaller", 0.032), ("small", "Small", 0.038),
        ("normal", "Normal", 0.045), ("large", "Large", 0.055), ("larger", "Larger", 0.066)]
    static let colors: [(String, String, Color)] = [("white", "White", .white), ("yellow", "Yellow", .yellow),
        ("gray", "Light gray", Color(white: 0.8)), ("black", "Black", .black)]
    static let shadows: [(String, String)] = [("none", "None"), ("drop", "Drop shadow"), ("outline", "Outline"), ("raised", "Raised")]
    static let bgs: [(String, String, Double)] = [("none", "Transparent", 0), ("semi", "Semi-transparent", 0.5), ("black", "Black", 1)]

    var item: Item { req.item }
    var current: Item? { episodes.firstIndex(where: { $0.Id == item.Id }).map { episodes[$0] } }
    var prevEp: Item? { episodes.firstIndex(where: { $0.Id == item.Id }).flatMap { $0 > 0 ? episodes[$0 - 1] : nil } }
    var nextEp: Item? { episodes.firstIndex(where: { $0.Id == item.Id }).flatMap { $0 + 1 < episodes.count ? episodes[$0 + 1] : nil } }

    var window: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow }

    /// Full screen for the video; leaving the player restores the window if the player made it full screen.
    func toggleFullScreen() {
        guard let w = window else { return }
        let on = w.styleMask.contains(.fullScreen)
        if !on { enteredFullScreen = true }
        w.toggleFullScreen(nil)
        isFullScreen = !on
    }

    func close() {
        if enteredFullScreen, let w = window, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        let done = model.watchedEnough
        model.stop()
        emby.playing = nil
        if done { Task { await emby.setPlayed(req.item.id, true) } }
    }

    /// Plays a neighbouring episode, keeping the current subtitle language.
    func play(_ ep: Item) {
        let lang = model.subStreams.first { $0.Index == model.sub }.map { DetailView.langName($0) }
        Task {
            let f = await emby.full(ep.id)
            let src = f?.MediaSources?.first
            var pick: Int?
            if let lang {
                let subs = (src?.MediaStreams ?? []).filter { $0.`Type` == "Subtitle" && DetailView.langName($0) == lang }
                let text = ["srt", "subrip", "vtt", "ass", "ssa"]
                pick = (subs.first { text.contains(($0.Codec ?? "").lowercased()) } ?? subs.first)?.Index
            }
            if model.watchedEnough { await emby.setPlayed(item.id, true) }
            model.stop()
            let q = UserDefaults.standard.integer(forKey: "defaultQuality")
            emby.playing = PlayRequest(item: ep, sourceId: src?.Id, sub: pick, maxBitrate: q > 0 ? q : nil,
                                       start: emby.resumeAt(ep))
        }
    }

    func poke() {
        showUI = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled && model.playing && panel == nil {
                withAnimation { showUI = false }
                // Full screen: hide the pointer with the controls; it comes back when the mouse moves
                if isFullScreen { NSCursor.setHiddenUntilMouseMoves(true) }
            }
        }
    }

    func fmt(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    var endClock: String {
        let left = max(0, model.duration - model.time) / Double(max(model.speed, 0.1))
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: Date().addingTimeInterval(left))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let p = model.player { AVPlayerViewRep(player: p, onLayer: model.attach).ignoresSafeArea() }
                else if model.error.isEmpty { Spinner(inPlayer: true).controlSize(.large) }
                if model.pipActive { pipPlaceholder }

                subtitleLayer(geo.size)

                if showUI || panel != nil {
                    LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.85)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea().allowsHitTesting(false)
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        bottomBar
                    }
                    .transition(.opacity)
                }

                if !model.error.isEmpty {
                    VStack(spacing: 12) {
                        Text(model.error).multilineTextAlignment(.center).frame(maxWidth: 420)
                        Button("Retry with transcoding") { Task { await model.start(emby, req, direct: false) } }
                    }
                }

                if showInfo { infoOverlay }
                cornerCards
                panelLayer
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if panel != nil { panel = nil }
                else if clickToPause { model.togglePlay(); poke() }
                else { withAnimation { showUI.toggle() } }
            }
        }
        .foregroundColor(.white)
        .onContinuousHover { _ in poke() }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) { model.togglePlay(); poke(); return .handled }
        .onKeyPress("f") { toggleFullScreen(); return .handled }
        .onKeyPress("i") { showInfo.toggle(); return .handled }
        // No screen saver / display sleep while a full-screen video is playing
        .onChange(of: model.playing && isFullScreen) { _, on in KeepAwake.set(on) }
        .onDisappear { KeepAwake.set(false) }
        .onKeyPress("p") { model.togglePiP(); return .handled }
        .onKeyPress("c") { if !model.chapterList.isEmpty { panel = panel == .chapters ? nil : .chapters }; return .handled }
        .task(id: showInfo) {
            while showInfo && !Task.isCancelled {
                infoLines = await model.playbackInfo()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task(id: showUpNext) {
            guard showUpNext, autoNext else { upNextLeft = 10; return }
            upNextLeft = 10
            while upNextLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if model.playing { upNextLeft -= 1 }
            }
            if showUpNext, let n = nextEp { play(n) }
        }
        .toolbar(.hidden, for: .windowToolbar)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in isFullScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in isFullScreen = false }
        .onKeyPress(.leftArrow) { model.skip(-Double(skipSecs)); poke(); return .handled }
        .onKeyPress(.rightArrow) { model.skip(Double(skipSecs)); poke(); return .handled }
        .onKeyPress(.escape) {
            // Esc: close a panel, else leave full screen (video keeps playing), else close the player
            if panel != nil { panel = nil } else if isFullScreen { toggleFullScreen() } else { close() }
            return .handled
        }
        .task {
            focused = true
            poke()
            if item.isEpisode, let sid = item.SeriesId { episodes = await emby.episodes(sid) }
        }
        .task { await model.start(emby, req) }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            if autoNext, let n = nextEp { play(n) } else { close() }
        }
    }

    // MARK: Subtitles drawn by the app

    @ViewBuilder func subtitleLayer(_ size: CGSize) -> some View {
        if model.loadingSubs {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Spinner(inPlayer: true).controlSize(.small)
                    Text("Loading subtitles…").font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(.bottom, size.height * subBottom / 100)
            }.frame(maxWidth: .infinity).allowsHitTesting(false)
        }
        if !model.caption.isEmpty {
            let fs = max(14, size.height * (Self.sizes.first { $0.0 == subTextSize }?.2 ?? 0.045))
            let color = Self.colors.first { $0.0 == subColor }?.2 ?? .white
            let shade: Color = subColor == "black" ? .white : .black
            VStack {
                Spacer()
                Text(model.caption)
                    .font(.system(size: fs, weight: .medium))
                    .foregroundColor(color)
                    .multilineTextAlignment(.center)
                    .modifier(SubShadow(style: subShadow, color: shade))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.black.opacity(Self.bgs.first { $0.0 == subBg }?.2 ?? 0))
                    .cornerRadius(4)
                    .padding(.horizontal, size.width * 0.08)
                    .padding(.bottom, size.height * subBottom / 100)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
        }
    }

    // MARK: Top bar

    var topBar: some View {
        HStack(spacing: 16) {
            BackPill { close() }.help("Back (Esc)")
            AsyncImage(url: emby.image(item.SeriesId ?? item.Id, "Logo", width: 400)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: { EmptyView() }
            .frame(maxWidth: 160, maxHeight: 40, alignment: .leading)
            Spacer()
            Slider(value: $model.volume, in: 0...1).frame(width: 160).tint(.white).controlSize(.small)
            Button { model.volume = model.volume > 0 ? 0 : 1 } label: {
                Image(systemName: model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 18))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 14)
    }

    // MARK: Bottom bar

    var episodeLine: String? {
        guard item.isEpisode else { return nil }
        return "S\(item.ParentIndexNumber ?? 0):E\(item.IndexNumber ?? 0) - \(item.Name)"
    }

    var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if let l = episodeLine { Text(l).font(.system(size: 16, weight: .medium)).opacity(0.85) }
                    Text(item.heroTitle).font(.system(size: 28, weight: .bold))
                }
                Spacer()
                HStack(spacing: 26) {
                    iconButton("captions.bubble", on: panel != nil) {
                        withAnimation(.easeOut(duration: 0.2)) { panel = panel == nil ? .subtitles : nil }
                    }.help("Subtitles, audio, quality & speed")
                }
            }

            Slider(value: Binding(get: { scrubbing ? scrub : model.time },
                                  set: { scrub = $0 }),
                   in: 0...max(model.duration, 1)) { editing in
                if editing { scrub = model.time; scrubbing = true }
                else { model.seek(to: scrub); scrubbing = false }
            }
            .tint(accent).controlSize(.small)
            .background(GeometryReader { g in
                Color.clear.onAppear { sliderW = g.size.width }.onChange(of: g.size.width) { _, w in sliderW = w }
            })
            .onContinuousHover { ph in
                if case .active(let p) = ph { hoverX = p.x } else { hoverX = nil }
            }
            .overlay(alignment: .bottomLeading) { scrubPreview }

            HStack {
                Text(fmt(scrubbing ? scrub : model.time))
                Spacer()
                Text("-\(fmt(max(0, model.duration - (scrubbing ? scrub : model.time))))  /  \(endClock)")
            }
            .font(.system(size: 14).monospacedDigit()).opacity(0.85)

            HStack(spacing: 30) {
                iconButton("backward.end.fill", size: 18) { if let p = prevEp { play(p) } else { model.seek(to: 0) } }
                    .help("Previous")
                iconButton("gobackward.\(skipSecs)", size: 22) { model.skip(-Double(skipSecs)) }.help("Back \(skipSecs) seconds")
                Button { model.togglePlay(); poke() } label: {
                    Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.white))
                        .contentShape(Circle())
                }.buttonStyle(.plain).help(model.playing ? "Pause (Space)" : "Play (Space)")
                iconButton("goforward.\(skipSecs)", size: 22) { model.skip(Double(skipSecs)) }.help("Forward \(skipSecs) seconds")
                iconButton("forward.end.fill", size: 18) { if let n = nextEp { play(n) } }
                    .opacity(nextEp == nil ? 0.35 : 1).disabled(nextEp == nil).help("Next")
                Spacer()
                extraButtons
                iconButton(isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", size: 18) {
                    toggleFullScreen()
                }.help(isFullScreen ? "Exit full screen (F)" : "Full screen (F)")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 34).padding(.bottom, 24)
    }

    func iconButton(_ name: String, size: CGFloat = 22, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { action(); poke() } label: {
            Image(systemName: name).font(.system(size: size, weight: .medium))
                .frame(width: size + 12, height: size + 12)
                .foregroundColor(on ? accent : .white)
                .background(Circle().fill(Color.white.opacity(on ? 0.12 : 0)))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: Panels

    @ViewBuilder var panelLayer: some View {
        switch panel {
        case .subtitles:
            HStack { Spacer(); mediaPanel }
                .padding(.top, 84).padding(.bottom, 190).padding(.trailing, 24)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .appearance:
            HStack { Spacer(); appearancePanel }.transition(.move(edge: .trailing))
        case .chapters:
            HStack { Spacer(); chaptersPanel }
                .padding(.top, 84).padding(.bottom, 190).padding(.trailing, 24)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case nil: EmptyView()
        }
    }

    func row(_ icon: String, _ title: String, sub: String? = nil, checked: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16))
                    if let sub { Text(sub).font(.system(size: 13)).foregroundColor(.secondary) }
                }
                Spacer()
                if checked { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)) }
            }
            .foregroundColor(checked ? accent : .white)
            .padding(.horizontal, 22).padding(.vertical, 11)
            .contentShape(Rectangle())
        }.buttonStyle(PanelRowStyle())
    }

    func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 4)
    }

    func panelDivider() -> some View { Divider().padding(.horizontal, 18).padding(.vertical, 6) }

    /// One side panel with everything the old Subtitles, Speed and Settings popups had.
    var mediaPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Subtitles")
                row("captions.bubble", "Off", checked: model.sub == nil) { Task { await model.setSub(emby, nil) } }
                ForEach(model.subStreams) { st in
                    row("captions.bubble", st.DisplayTitle ?? "Track \(st.Index)", checked: model.sub == st.Index) {
                        Task { await model.setSub(emby, st.Index) }
                    }
                }
                HStack(spacing: 18) {
                    Image(systemName: "timer").font(.system(size: 18)).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subtitle Offset").font(.system(size: 16))
                        Text("\(model.subOffset) ms").font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button { model.subOffset -= 100 } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        .help("Show subtitles 100 ms earlier")
                    Button { model.subOffset = 0 } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain)
                        .opacity(model.subOffset == 0 ? 0.3 : 1).help("Reset offset")
                    Button { model.subOffset += 100 } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain)
                        .help("Show subtitles 100 ms later")
                }
                .font(.system(size: 18))
                .padding(.horizontal, 22).padding(.vertical, 9)
                row("textformat.size", "Subtitle Appearance") { withAnimation { panel = .appearance } }

                if model.audioStreams.count > 0 {
                    panelDivider()
                    sectionTitle("Audio")
                    ForEach(model.audioStreams) { st in
                        row("waveform", st.DisplayTitle ?? "Track \(st.Index)", checked: model.audio == st.Index) {
                            Task { await model.setAudio(emby, st.Index) }
                        }
                    }
                }

                panelDivider()
                sectionTitle("Quality")
                ForEach([(0, "Original"), (8_000_000, "1080p · 8 Mbps"), (4_000_000, "720p · 4 Mbps"), (1_500_000, "480p · 1.5 Mbps")], id: \.0) { q in
                    row("dial.medium", q.1, checked: model.quality == q.0) { Task { await model.setQuality(emby, q.0) } }
                }

                panelDivider()
                sectionTitle("Speed")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0] as [Float], id: \.self) { r in
                        let on = model.speed == r
                        Button { model.setSpeed(r) } label: {
                            Text(r == 1 ? "1×" : String(format: "%g×", r)).font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .foregroundColor(on ? .black : .white)
                                .background(RoundedRectangle(cornerRadius: 8).fill(on ? accent : Color.white.opacity(0.1)))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help(r == 1 ? "Normal speed" : "\(String(format: "%g", r))× speed")
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 6)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 340)
        .background(.ultraThinMaterial.opacity(0.95))
        .background(Color(white: 0.15).opacity(0.85))
        .cornerRadius(14)
        .environment(\.colorScheme, .dark)
        .onTapGesture {}   // keep taps inside the panel
    }

    func dropdown<T: Hashable>(_ label: String, _ sel: Binding<T>, _ opts: [(T, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 15)).foregroundColor(.white.opacity(0.85))
            Menu {
                ForEach(opts, id: \.0) { o in
                    Button { sel.wrappedValue = o.0 } label: {
                        if sel.wrappedValue == o.0 { Label(o.1, systemImage: "checkmark") } else { Text(o.1) }
                    }
                }
            } label: {
                HStack {
                    Text(opts.first { $0.0 == sel.wrappedValue }?.1 ?? "").font(.system(size: 16))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.white.opacity(0.1)).cornerRadius(6)
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        }
    }

    var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                Button { withAnimation { panel = .subtitles } } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)) }
                    .buttonStyle(.plain)
                Text("Subtitle Appearance").font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal, 28).padding(.vertical, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dropdown("Text size", $subTextSize, Self.sizes.map { ($0.0, $0.1) })
                    dropdown("Text color", $subColor, Self.colors.map { ($0.0, $0.1) })
                    dropdown("Drop shadow", $subShadow, Self.shadows)
                    dropdown("Background color", $subBg, Self.bgs.map { ($0.0, $0.1) })
                    Text("Subtitle Position").font(.system(size: 20, weight: .bold)).padding(.top, 8)
                    VStack(alignment: .leading, spacing: 8) {
                        dropdown("Bottom Edge Position", $subBottom, [0, 5, 10, 15, 20, 25, 30].map { (Double($0), "\($0)%") })
                        Text("Set the vertical position of the subtitles relative to the bottom of the screen.")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Button("Reset to Default") {
                        subTextSize = "normal"; subColor = "white"; subShadow = "drop"; subBg = "none"; subBottom = 10
                    }.padding(.top, 6)
                }
                .padding(.horizontal, 28).padding(.bottom, 28)
            }
        }
        .frame(width: 400)
        .frame(maxHeight: .infinity)
        .background(Color(white: 0.16).opacity(0.97))
        .environment(\.colorScheme, .dark)
        .onTapGesture {}
    }
}

extension PlayerView {
    // MARK: Extra controls

    var extraButtons: some View {
        HStack(spacing: 22) {
            if !model.chapterList.isEmpty {
                iconButton("list.bullet.rectangle", size: 18, on: panel == .chapters) {
                    withAnimation(.easeOut(duration: 0.2)) { panel = panel == .chapters ? nil : .chapters }
                }.help("Chapters (C)")
            }
            iconButton("info.circle", size: 18, on: showInfo) { showInfo.toggle() }.help("Playback info (I)")
            if model.pipSupported {
                iconButton(model.pipActive ? "pip.exit" : "pip.enter", size: 18, on: model.pipActive) { model.togglePiP() }
                    .help("Picture in picture (P)")
            }
        }
    }

    var pipPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "pip").font(.system(size: 44))
            Text("Playing in picture in picture").font(.system(size: 16, weight: .medium))
        }.opacity(0.6).allowsHitTesting(false)
    }

    // MARK: Scrub preview

    @ViewBuilder var scrubPreview: some View {
        let x: CGFloat? = scrubbing ? CGFloat(scrub / max(model.duration, 1)) * sliderW : hoverX
        if let x, model.duration > 0 {
            let t = Double(max(0, min(x, sliderW)) / max(sliderW, 1)) * model.duration
            let img = model.hasThumbs ? model.thumb(at: t) : nil
            let w: CGFloat = img == nil ? 64 : 220
            VStack(spacing: 4) {
                if let img {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: w).cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.6), lineWidth: 1))
                }
                Text(fmt(t)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
            }
            .frame(width: w)
            .offset(x: min(max(0, x - w / 2), max(0, sliderW - w)), y: -26)
            .allowsHitTesting(false)
        }
    }

    // MARK: Intro / up next (bottom-right corner)

    var showUpNext: Bool {
        guard item.isEpisode, nextEp != nil, !upNextCancelled, model.duration > 120 else { return false }
        let from = model.creditsStart ?? (model.duration - 30)
        return model.time >= from && model.time < model.duration - 0.5
    }

    var cornerCards: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Spacer()
            if model.skippedIntro {
                HStack(spacing: 12) {
                    Image(systemName: "forward.fill")
                    Text("Intro skipped").font(.system(size: 15, weight: .semibold))
                    Button("Watch intro") { model.watchIntro() }.buttonStyle(.plain)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(accent)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .transition(.opacity)
            } else if model.inIntro {
                Button { model.skipIntro() } label: {
                    Text("Skip Intro").font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                }.buttonStyle(.plain)
            }
            if showUpNext, let n = nextEp { upNextCard(n) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 34)
        .padding(.bottom, showUI ? 200 : 40)
        .animation(.easeOut(duration: 0.2), value: model.skippedIntro)
    }

    func upNextCard(_ n: Item) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: emby.image(n.Id, "Primary", width: 400)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Color.white.opacity(0.1) }
            .frame(width: 160, height: 90).clipped().cornerRadius(6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Up next").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                Text("S\(n.ParentIndexNumber ?? 0):E\(n.IndexNumber ?? 0) · \(n.Name)")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(2).frame(maxWidth: 220, alignment: .leading)
                HStack(spacing: 10) {
                    Button { play(n) } label: {
                        Text(autoNext ? "Play now (\(upNextLeft))" : "Play now").font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black).padding(.horizontal, 14).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                    }.buttonStyle(.plain)
                    Button { upNextCancelled = true } label: {
                        Text("Cancel").font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.15)))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.8)))
        .environment(\.colorScheme, .dark)
        .onTapGesture {}
    }

    // MARK: Playback info

    var infoOverlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Playback info").font(.system(size: 13, weight: .bold))
                    ForEach(Array(infoLines.enumerated()), id: \.offset) { _, l in
                        HStack(alignment: .top, spacing: 10) {
                            Text(l.0).foregroundColor(.white.opacity(0.6)).frame(width: 120, alignment: .leading)
                            Text(l.1).frame(maxWidth: 260, alignment: .leading)
                        }
                    }
                }
                .font(.system(size: 12).monospacedDigit())
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.75)))
                Spacer()
            }
            Spacer()
        }
        .padding(.top, 70).padding(.leading, 20)
        .allowsHitTesting(false)
    }

    // MARK: Chapters panel

    var chaptersPanel: some View {
        let list = model.chapterList
        let cur = list.lastIndex { $0.c.start <= model.time }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Chapters")
                ForEach(Array(list.enumerated()), id: \.offset) { k, e in
                    chapterRow(e.i, e.c, current: k == cur)
                }
            }.padding(.vertical, 12)
        }
        .frame(width: 380)
        .background(.ultraThinMaterial.opacity(0.95))
        .background(Color(white: 0.15).opacity(0.85))
        .cornerRadius(14)
        .environment(\.colorScheme, .dark)
        .onTapGesture {}
    }

    func chapterRow(_ i: Int, _ c: Chapter, current: Bool) -> some View {
        Button { model.seek(to: c.start); panel = nil } label: {
            HStack(spacing: 14) {
                Group {
                    if let tag = c.ImageTag {
                        AsyncImage(url: emby.chapterImage(item.Id, i, tag)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Color.white.opacity(0.08) }
                    } else { Color.white.opacity(0.08) }
                }
                .frame(width: 112, height: 63).clipped().cornerRadius(5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.Name ?? "Chapter \(i + 1)").font(.system(size: 15)).lineLimit(2)
                    Text(fmt(c.start)).font(.system(size: 13).monospacedDigit()).foregroundColor(.secondary)
                }
                Spacer()
            }
            .foregroundColor(current ? accent : .white)
            .padding(.horizontal, 18).padding(.vertical, 7)
            .contentShape(Rectangle())
        }.buttonStyle(PanelRowStyle())
    }
}

struct PanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : 0))
    }
}

struct SubShadow: ViewModifier {
    let style: String
    let color: Color
    func body(content: Content) -> some View {
        switch style {
        case "drop":
            content.shadow(color: color.opacity(0.9), radius: 2, x: 1.5, y: 1.5).shadow(color: color.opacity(0.6), radius: 4)
        case "outline":
            content.shadow(color: color, radius: 0, x: 1, y: 1).shadow(color: color, radius: 0, x: -1, y: -1)
                .shadow(color: color, radius: 0, x: 1, y: -1).shadow(color: color, radius: 0, x: -1, y: 1)
        case "raised":
            content.shadow(color: color, radius: 0, x: 1, y: 2)
        default:
            content
        }
    }
}

/// AppKit video surface with no built-in controls; the SwiftUI overlay draws the UI.
/// (SwiftUI's VideoPlayer crashes on load on this macOS version.)
/// A plain AVPlayerLayer (picture-in-picture needs the layer). Clicks pass through to SwiftUI (click = play/pause).
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct AVPlayerViewRep: NSViewRepresentable {
    let player: AVPlayer
    var onLayer: (AVPlayerLayer) -> Void = { _ in }
    func makeNSView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.playerLayer.player = player
        let cb = onLayer, l = v.playerLayer
        DispatchQueue.main.async { cb(l) }
        return v
    }
    func updateNSView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

/// Loading spinner drawn by SwiftUI. The system ProgressView is an AppKit view that always draws on top,
/// so a spinner on a page behind the player showed through the video.
struct Spinner: View {
    var inPlayer = false
    @ObservedObject private var playback = PlaybackFlag.shared
    @Environment(\.controlSize) private var size
    var d: CGFloat { size == .small || size == .mini ? 16 : size == .large ? 40 : 26 }
    var body: some View {
        // Pages behind the player live in separate AppKit hosting views, so their spinners can show
        // through the video: don't draw them at all while something is playing.
        if playback.active && !inPlayer { EmptyView() } else {
            wheel
        }
    }

    /// Rotation comes from the clock, not a repeatForever animation: such an animation also drives the
    /// view's removal, so the spinner never finished disappearing and stayed over the playing video.
    var wheel: some View {
        TimelineView(.animation) { ctx in
            let angle = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
            Circle()
                .trim(from: 0.08, to: 0.8)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: max(2, d / 9), lineCap: .round))
                .frame(width: d, height: d)
                .rotationEffect(.degrees(angle))
        }
    }
}

/// True while the video player is on screen.
final class PlaybackFlag: ObservableObject {
    static let shared = PlaybackFlag()
    @Published var active = false
}


/// Holds an IOKit assertion that stops the screen saver and display sleep.
enum KeepAwake {
    private static var id: IOPMAssertionID = 0
    static func set(_ on: Bool) {
        if on, id == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "EmbyFlix is playing a video in full screen" as CFString, &id)
        } else if !on, id != 0 {
            IOPMAssertionRelease(id)
            id = 0
        }
    }
}
