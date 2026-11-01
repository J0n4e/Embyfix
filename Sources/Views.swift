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
            .background(active ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.12)))
            .clipShape(Capsule())
    }
    func circleButton() -> some View {
        self.font(.title3).padding(10)
            .background(Color.white.opacity(0.2)).clipShape(Circle())
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
            if emby.loggedIn { HomeView() } else { LoginView() }
            if let req = emby.playing {
                PlayerView(req: req).id(req.id).zIndex(10)
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var emby: Emby
    @State private var server = ""
    @State private var user = ""
    @State private var pw = ""
    @State private var error = ""
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("EMBYFLIX").font(.system(size: 44, weight: .black)).foregroundStyle(.tint)
                Text("Sign In").font(.title.bold()).padding(.bottom, 6)
                TextField("Server (e.g. 192.168.1.10:8096)", text: $server)
                TextField("Username", text: $user)
                SecureField("Password", text: $pw).onSubmit(go)
                Button(action: go) {
                    Text("Sign In").bold().frame(maxWidth: .infinity).padding(8)
                }.buttonStyle(.borderedProminent)
                if !error.isEmpty { Text(error).foregroundColor(.orange).font(.caption) }
            }
            .textFieldStyle(.roundedBorder).controlSize(.large)
            .frame(width: 340).padding(36)
            .background(Color.black.opacity(0.75)).cornerRadius(8)
        }
    }
    func go() {
        Task {
            do { try await emby.login(server: server, user: user, pw: pw) }
            catch { self.error = "Couldn't sign in. Check server address and credentials." }
        }
    }
}

// MARK: - Sidebar shell + search

struct HomeView: View {
    @EnvironmentObject var emby: Emby
    @State private var sel = "home"
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showSettings = false
    @State private var showTheme = false
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
                Section("My Media") {
                    ForEach(emby.libs.filter { $0.visible }) { lib in
                        Label(lib.title, systemImage: icon(lib)).tag(lib.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 280)
            .safeAreaInset(edge: .top) {
                Text("EMBYFLIX").font(.headline.weight(.black)).foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.help("Customize libraries")
                    Button { showTheme = true } label: { Image(systemName: "paintpalette") }.help("Appearance")
                    Spacer()
                    Button("Sign Out") { emby.logout() }
                }.buttonStyle(.plain).font(.caption).padding(10)
            }
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if !query.isEmpty { SearchView(query: query) }
                    else if sel == "home" { HomeContent(reloadToken: reloadToken) }
                    else if let lib = emby.libs.first(where: { $0.id == sel }) { LibraryView(lib: lib).id(lib.id) }
                    else { Color.black }
                }
                .navigationDestination(for: Item.self) { DetailView(item: $0) }
            }
            .safeAreaInset(edge: .top, spacing: 0) { SearchBar(query: $query) }
        }
        .task { await emby.loadLibs() }
        .onChange(of: sel) { path = NavigationPath(); query = "" }
        .sheet(isPresented: $showSettings) { LibrarySettings { reloadToken += 1 } }
        .sheet(isPresented: $showTheme) { AppearanceSheet() }
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
                TextField("Search movies, shows…", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(0.12)).clipShape(Capsule())
            .frame(width: 280)
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
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
                if busy { ProgressView() }
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

struct AppearanceSheet: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("accent") private var accent = "red"
    @AppStorage("bg") private var bg = "black"

    func swatches(_ list: [(String, Color)], selection: Binding<String>) -> some View {
        HStack(spacing: 14) {
            ForEach(list, id: \.0) { name, color in
                Button { selection.wrappedValue = name } label: {
                    Circle().fill(color).frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.white, lineWidth: selection.wrappedValue == name ? 3 : 0))
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }.buttonStyle(.plain).help(name.capitalized)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Appearance").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Accent color").font(.headline)
            swatches(Theme.accents, selection: $accent)
            Text("Background").font(.headline)
            swatches(Theme.backgrounds, selection: $bg)
        }
        .padding(24).frame(width: 440)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.title).font(.title3.bold()).padding(.leading, 40)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(row.items) { PosterCard(item: $0) }
                            }.padding(.horizontal, 40)
                        }
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(60) }
            }.padding(.bottom, 40)
        }
        .background(bg)
        .task(id: reloadToken) { rows = await emby.loadHome(); loading = false }
    }
}

struct Hero: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    let items: [Item]
    @State private var index = 0
    var body: some View {
        let item = items[index % items.count]
        ZStack(alignment: .bottomLeading) {
            Backdrop(id: item.backdropId ?? item.Id).frame(height: 460).clipped()
                .id("b" + item.id).transition(.opacity)
            LinearGradient(colors: [Color.clear, bg], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(item.heroTitle).font(.system(size: 40, weight: .heavy))
                if item.SeriesName != nil {
                    Text("S\(item.ParentIndexNumber ?? 0)·E\(item.IndexNumber ?? 0)  \(item.Name)")
                        .font(.headline).foregroundColor(.secondary)
                }
                Text(item.Overview ?? "").lineLimit(3).frame(maxWidth: 520, alignment: .leading)
                HStack(spacing: 10) {
                    Button { Task { await emby.play(item) } } label: {
                        Label("Play", systemImage: "play.fill").bold()
                            .padding(.horizontal, 22).padding(.vertical, 8)
                            .background(.white).foregroundColor(.black).cornerRadius(4)
                    }.buttonStyle(.plain)
                    NavigationLink(value: item) {
                        Label("More Info", systemImage: "info.circle").bold()
                            .padding(.horizontal, 22).padding(.vertical, 8)
                            .background(Color.gray.opacity(0.5)).cornerRadius(4)
                    }.buttonStyle(.plain)
                }
            }.padding(40).id("t" + item.id).transition(.opacity)
        }
        .frame(height: 460)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    Circle().fill(i == index % items.count ? Color.white : Color.white.opacity(0.35))
                        .frame(width: 8, height: 8)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.8)) { index = i } }
                }
            }.padding(40)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 1.0)) { index += 1 }
            }
        }
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
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: emby.image(item.posterId, width: 360)) { p in
                    p.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack { Color(white: 0.15); Text(item.Name).font(.caption).padding(6) }
                }
                .frame(width: 150, height: 225).clipped()
                .opacity(played ? 0.6 : 1)
                if played {
                    ZStack {
                        Circle().fill(.tint)
                        Image(systemName: "checkmark").font(.caption.bold()).foregroundColor(.white)
                    }.frame(width: 22, height: 22).padding(6).shadow(radius: 3)
                }
            }
            .overlay(alignment: .bottom) {
                if let pct = item.UserData?.PlayedPercentage, pct > 0, pct < 100, !played {
                    ProgressView(value: pct / 100).padding(.horizontal, 6).padding(.bottom, 6)
                }
            }
            .cornerRadius(4)
            .scaleEffect(hover ? 1.12 : 1).shadow(radius: hover ? 12 : 0)
            .animation(.easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0 }
            .zIndex(hover ? 1 : 0)
            .help(item.Name)
        }.buttonStyle(.plain)
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

    init(lib: LibPref) {
        self.lib = lib
        let d = UserDefaults.standard.dictionary(forKey: "lf-" + lib.id) ?? [:]
        _sort = State(initialValue: d["sort"] as? String ?? "name")
        _desc = State(initialValue: d["desc"] as? Bool ?? false)
        _watch = State(initialValue: d["watch"] as? String ?? "all")
        _genre = State(initialValue: d["genre"] as? String ?? "")
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
        let d: [String: Any] = ["sort": sort, "desc": desc, "watch": watch, "genre": genre]
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
        .onChange(of: "\(sort)|\(desc)|\(watch)|\(genre)") { save() }
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
            Menu {
                Button("Refresh") { Task { await load(reset: true) } }
            } label: { Image(systemName: "ellipsis").pill() }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    var grid: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                ForEach(items) { it in
                    PosterCard(item: it).onAppear {
                        if it.id == items.last?.id { Task { await load(reset: false) } }
                    }
                }
            }
            if loading { ProgressView() }
            else if items.isEmpty { Text("Nothing here.").foregroundColor(.secondary).padding(40) }
        }
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

struct LibrarySettings: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.dismiss) var dismiss
    var onDone: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customize Libraries").font(.title2.bold())
                Spacer()
                Button("Done") { emby.saveLibs(); onDone(); dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            List {
                ForEach($emby.libs) { $lib in
                    HStack(spacing: 12) {
                        Toggle("Show", isOn: $lib.visible)
                        Toggle("Home row", isOn: $lib.onHome).disabled(!lib.visible)
                        TextField(lib.name, text: $lib.title)
                        Picker("", selection: $lib.style) {
                            Text("Latest").tag("latest")
                            Text("Top Rated").tag("top")
                            Text("Random").tag("random")
                            Text("A–Z").tag("az")
                        }.labelsHidden().frame(width: 110)
                    }.padding(.vertical, 4)
                }.onMove { emby.libs.move(fromOffsets: $0, toOffset: $1) }
            }
            Text("Drag rows to reorder. “Show” puts the library in the sidebar; “Home row” adds a row on the home screen.")
                .font(.caption).foregroundColor(.secondary).padding(10)
        }
        .frame(width: 680, height: 460)
    }
}

// MARK: - Detail / movie info

struct CastTile: View {
    @EnvironmentObject var emby: Emby
    let p: Full.Person
    var body: some View {
        VStack(spacing: 4) {
            AsyncImage(url: emby.image(p.Id, width: 300)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack { Color(white: 0.15); Image(systemName: "person.fill").foregroundColor(.secondary) }
            }
            .frame(width: 130, height: 175).clipped().cornerRadius(6)
            Text(p.Name).font(.caption).lineLimit(1)
            Text(p.Role ?? p.`Type` ?? "").font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }.frame(width: 130)
    }
}

struct DetailView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.appBG) var bg
    let item: Item
    @State private var full: Full?
    @State private var kids: [Item] = []
    @State private var seasonItems: [Item] = []
    @State private var epLangs: [(code: String, name: String)] = []
    @AppStorage("episodeSubLang") private var epSubLang = ""
    @State private var similar: [Item] = []
    @State private var srcIdx = 0
    @State private var audioIdx = -1
    @State private var subIdx = -1
    @State private var quality = 0
    @State private var season: Int? = nil

    var sources: [MSource] { full?.MediaSources ?? [] }
    var src: MSource? { sources.indices.contains(srcIdx) ? sources[srcIdx] : nil }
    func streams(_ t: String) -> [MStream] { (src?.MediaStreams ?? []).filter { $0.`Type` == t } }
    var defaultAudio: Int {
        let a = streams("Audio")
        return (a.first(where: { $0.IsDefault == true }) ?? a.first)?.Index ?? -1
    }
    var simple: Bool { item.isSeries || item.isBox }

    func playNow() {
        if simple { Task { await emby.play(item) }; return }
        let audioChanged = audioIdx >= 0 && audioIdx != defaultAudio
        emby.playing = PlayRequest(item: item, sourceId: src?.Id,
                                   audio: audioChanged ? audioIdx : nil,
                                   sub: subIdx >= 0 ? subIdx : nil,
                                   maxBitrate: quality > 0 ? quality : nil)
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
            if item.isSeries {
                async let eps = emby.episodes(item.id)
                async let ss = emby.seasons(item.id)
                kids = await eps; seasonItems = await ss
                if let first = kids.first { epLangs = Self.subLangs(await emby.full(first.id)) }
            }
            else if item.isBox { kids = await emby.children(item.id) }
            if !item.isEpisode { similar = await emby.similar(item.id) }
        }
        .onChange(of: srcIdx) { audioIdx = defaultAudio; subIdx = -1 }
    }

    // Header: poster + info + pickers + buttons
    var header: some View {
        HStack(alignment: .top, spacing: 28) {
            AsyncImage(url: emby.image(item.id, width: 500)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { ZStack { Color(white: 0.15); Text(item.Name).padding() } }
            .frame(width: item.isEpisode ? 320 : 190, height: item.isEpisode ? 180 : 285)
            .clipped().cornerRadius(6).shadow(radius: 10)
            VStack(alignment: .leading, spacing: 14) {
                Text(item.Name).font(.system(size: 34, weight: .bold))
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
                Label("Play", systemImage: "play.fill").bold()
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(.white).foregroundColor(.black).clipShape(Capsule())
            }.buttonStyle(.plain)
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
    func playEpisode(_ ep: Item) {
        if epSubLang.isEmpty { emby.playing = PlayRequest(item: ep); return }
        Task {
            let f = await emby.full(ep.id)
            let src = f?.MediaSources?.first
            let subs = (src?.MediaStreams ?? []).filter {
                $0.`Type` == "Subtitle" && Self.langName($0).lowercased() == epSubLang }
            let text = ["srt", "subrip", "vtt", "ass", "ssa"]
            let pick = subs.first { text.contains(($0.Codec ?? "").lowercased()) } ?? subs.first
            emby.playing = PlayRequest(item: ep, sourceId: src?.Id, sub: pick?.Index)
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
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: selected ? 3 : 0))
                .shadow(radius: 6)
                Text(title).font(.body).foregroundColor(selected ? .primary : .secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var seasonRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons").font(.title3.bold()).padding(.horizontal, 40)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(seasonNumbers, id: \.self) { n in seasonPoster(n) }
                }.padding(.horizontal, 40).padding(.vertical, 4)
            }
        }
    }

    var episodesHeader: some View {
        let multi: Bool = seasonNumbers.count > 1
        let heading: String = multi ? seasonTitle(currentSeason) : "Episodes"
        return HStack(spacing: 16) {
            Text(heading).font(.title3.bold())
            Spacer()
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
                if played { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).font(.title3) }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 40)
        .contextMenu {
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
            ForEach(eps) { ep in episodeRow(ep) }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) { ForEach(people) { CastTile(p: $0) } }.padding(.horizontal, 40)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) { ForEach(similar) { PosterCard(item: $0) } }.padding(.horizontal, 40)
                }
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
    // Current state shown in the player menus
    @Published var streams: [MStream] = []
    @Published var sub: Int? = nil
    @Published var audio: Int? = nil
    @Published var quality = 0
    @Published var speed: Float = 1
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
        self.req = req
        sub = req.sub; quality = req.maxBitrate ?? 0
        if streams.isEmpty, let f = await emby.full(req.item.id) {
            let src = f.MediaSources?.first { $0.Id == req.sourceId } ?? f.MediaSources?.first
            streams = src?.MediaStreams ?? []
        }
        let auds = streams.filter { $0.`Type` == "Audio" }
        audio = req.audio ?? (auds.first { $0.IsDefault == true } ?? auds.first)?.Index
        var req = req
        // Text subtitles are drawn by the app; only image subtitles are burned in by the server.
        if let sub = req.sub, let c = await emby.subtitleCues(req.item.id, req.sourceId, sub) {
            cues = c; req.sub = nil
        }
        guard let u = await emby.resolveStream(req, direct: direct) else {
            error = "Couldn't get a stream from the server."; return
        }
        let it = AVPlayerItem(url: u)
        obs = it.observe(\.status, options: [.new]) { [weak self] i, _ in
            if i.status == .failed {
                let m = i.error?.localizedDescription ?? "Playback failed."
                Task { @MainActor in self?.error = m }
            }
            if i.status == .readyToPlay {
                Task { @MainActor in
                    guard let self, self.pendingSeek > 0 else { return }
                    let t = self.pendingSeek; self.pendingSeek = 0
                    await self.player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
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

    func setSub(_ emby: Emby, _ idx: Int?) async {
        guard idx != sub, let r = req else { return }
        // Text subtitles switch instantly; image subtitles need a server burn-in restart.
        if let idx {
            if let c = await emby.subtitleCues(r.item.id, r.sourceId, idx) {
                cues = c; sub = idx; req?.sub = idx; updateCaption(now)
            } else {
                await restart(emby) { $0.sub = idx }
            }
        } else {
            let wasBurned = cues.isEmpty && sub != nil
            cues = []; caption = ""; sub = nil; req?.sub = nil
            if wasBurned { await restart(emby) { $0.sub = nil } }
        }
    }

    func setAudio(_ emby: Emby, _ idx: Int) async {
        guard idx != audio else { return }
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
        if isPlaying != playing { playing = isPlaying }
        updateCaption(t)
    }

    func togglePlay() {
        guard let p = player else { return }
        if p.rate > 0 { p.pause() } else { p.play() }
        playing = p.rate > 0
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
        if let o = timeObs { player?.removeTimeObserver(o) }
        timeObs = nil
        player?.pause(); player = nil; obs = nil; caption = ""
    }
}

struct PlayerView: View {
    @EnvironmentObject var emby: Emby
    @StateObject private var model = PlayerModel()
    let req: PlayRequest

    enum Panel { case subtitles, appearance, speed, settings }
    @State private var panel: Panel?
    @State private var showUI = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrub: Double = 0
    @State private var episodes: [Item] = []
    @FocusState private var focused: Bool

    // Subtitle appearance (defaults: normal size, white, drop shadow, transparent, 10% from bottom)
    @AppStorage("subTextSize") private var subTextSize = "normal"
    @AppStorage("subColor") private var subColor = "white"
    @AppStorage("subShadowStyle") private var subShadow = "drop"
    @AppStorage("subBg") private var subBg = "none"
    @AppStorage("subBottom") private var subBottom = 10.0

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

    func close() {
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
            emby.playing = PlayRequest(item: ep, sourceId: src?.Id, sub: pick)
        }
    }

    func poke() {
        showUI = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled && model.playing && panel == nil { withAnimation { showUI = false } }
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
                if let p = model.player { AVPlayerViewRep(player: p).ignoresSafeArea() }
                else if model.error.isEmpty { ProgressView().controlSize(.large) }

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

                panelLayer
            }
            .contentShape(Rectangle())
            .onTapGesture { if panel != nil { panel = nil } else { model.togglePlay(); poke() } }
        }
        .foregroundColor(.white)
        .onContinuousHover { _ in poke() }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) { model.togglePlay(); poke(); return .handled }
        .onKeyPress(.leftArrow) { model.skip(-10); poke(); return .handled }
        .onKeyPress(.rightArrow) { model.skip(10); poke(); return .handled }
        .onKeyPress(.escape) { if panel != nil { panel = nil } else { close() }; return .handled }
        .task {
            focused = true
            poke()
            if item.isEpisode, let sid = item.SeriesId { episodes = await emby.episodes(sid) }
        }
        .task { await model.start(emby, req) }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            if let n = nextEp { play(n) } else { close() }
        }
    }

    // MARK: Subtitles drawn by the app

    @ViewBuilder func subtitleLayer(_ size: CGSize) -> some View {
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
            Button { close() } label: { Image(systemName: "chevron.left").font(.system(size: 22, weight: .semibold)) }
                .buttonStyle(.plain).help("Back")
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
                    iconButton("captions.bubble", on: panel == .subtitles || panel == .appearance) {
                        panel = panel == .subtitles ? nil : .subtitles
                    }.help("Subtitles")
                    iconButton("gauge.with.dots.needle.67percent", on: panel == .speed) {
                        panel = panel == .speed ? nil : .speed
                    }.help("Playback speed")
                    iconButton("gearshape.fill", on: panel == .settings) {
                        panel = panel == .settings ? nil : .settings
                    }.help("Settings")
                }
            }

            Slider(value: Binding(get: { scrubbing ? scrub : model.time },
                                  set: { scrub = $0 }),
                   in: 0...max(model.duration, 1)) { editing in
                if editing { scrub = model.time; scrubbing = true }
                else { model.seek(to: scrub); scrubbing = false }
            }
            .tint(.white).controlSize(.small)

            HStack {
                Text(fmt(scrubbing ? scrub : model.time))
                Spacer()
                Text("-\(fmt(max(0, model.duration - (scrubbing ? scrub : model.time))))  /  \(endClock)")
            }
            .font(.system(size: 14).monospacedDigit()).opacity(0.85)

            HStack(spacing: 30) {
                iconButton("backward.end.fill", size: 18) { if let p = prevEp { play(p) } else { model.seek(to: 0) } }
                    .help("Previous")
                iconButton("gobackward.10", size: 22) { model.skip(-10) }.help("Back 10 seconds")
                iconButton(model.playing ? "pause.fill" : "play.fill", size: 26) { model.togglePlay() }
                    .help(model.playing ? "Pause" : "Play")
                iconButton("goforward.10", size: 22) { model.skip(10) }.help("Forward 10 seconds")
                iconButton("forward.end.fill", size: 18) { if let n = nextEp { play(n) } }
                    .opacity(nextEp == nil ? 0.35 : 1).disabled(nextEp == nil).help("Next")
                Spacer()
                iconButton("arrow.up.left.and.arrow.down.right", size: 18) {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }.help("Full screen")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 34).padding(.bottom, 24)
    }

    func iconButton(_ name: String, size: CGFloat = 22, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { action(); poke() } label: {
            Image(systemName: name).font(.system(size: size, weight: .medium))
                .frame(width: size + 12, height: size + 12)
                .foregroundColor(on ? .accentColor : .white)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: Panels

    @ViewBuilder var panelLayer: some View {
        switch panel {
        case .subtitles: popup { subtitlesPanel }
        case .speed: popup { speedPanel }
        case .settings: popup { settingsPanel }
        case .appearance:
            HStack { Spacer(); appearancePanel }.transition(.move(edge: .trailing))
        case nil: EmptyView()
        }
    }

    func popup<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) { c() }
                    .padding(.vertical, 12)
                    .frame(width: 330)
                    .background(.ultraThinMaterial.opacity(0.95))
                    .background(Color(white: 0.15).opacity(0.85))
                    .cornerRadius(14)
                    .environment(\.colorScheme, .dark)
                    .onTapGesture {}   // keep taps inside the panel
            }
            .padding(.trailing, 30).padding(.bottom, 190)
        }
    }

    func panelTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 16, weight: .semibold)).foregroundColor(.secondary)
            .frame(maxWidth: .infinity).padding(.bottom, 8)
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
            .padding(.horizontal, 22).padding(.vertical, 11)
            .contentShape(Rectangle())
        }.buttonStyle(PanelRowStyle())
    }

    var subtitlesPanel: some View {
        Group {
            panelTitle("Subtitles")
            row("textformat.size", "Subtitle Appearance") { withAnimation { panel = .appearance } }
            HStack(spacing: 18) {
                Image(systemName: "timer").font(.system(size: 18)).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subtitle Offset").font(.system(size: 16))
                    Text("\(model.subOffset) ms").font(.system(size: 13)).foregroundColor(.secondary)
                }
                Spacer()
                Button { model.subOffset -= 100 } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                Button { model.subOffset = 0 } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain)
                    .opacity(model.subOffset == 0 ? 0.3 : 1)
                Button { model.subOffset += 100 } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain)
            }
            .font(.system(size: 18))
            .padding(.horizontal, 22).padding(.vertical, 9)
            Divider().padding(.horizontal, 18).padding(.vertical, 4)
            ScrollView {
                VStack(spacing: 0) {
                    row("captions.bubble", "Off", checked: model.sub == nil) { Task { await model.setSub(emby, nil) } }
                    ForEach(model.subStreams) { st in
                        row("captions.bubble", st.DisplayTitle ?? "Track \(st.Index)", checked: model.sub == st.Index) {
                            Task { await model.setSub(emby, st.Index) }
                        }
                    }
                }
            }.frame(maxHeight: 300).fixedSize(horizontal: false, vertical: true)
        }
    }

    var speedPanel: some View {
        Group {
            panelTitle("Playback Speed")
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0] as [Float], id: \.self) { r in
                row("gauge.with.dots.needle.67percent", r == 1 ? "Normal" : String(format: "%gx", r),
                    checked: model.speed == r) { model.setSpeed(r) }
            }
        }
    }

    var settingsPanel: some View {
        Group {
            panelTitle("Settings")
            if model.audioStreams.count > 0 {
                Text("Audio").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).padding(.horizontal, 22).padding(.top, 4)
                ForEach(model.audioStreams) { st in
                    row("waveform", st.DisplayTitle ?? "Track \(st.Index)", checked: model.audio == st.Index) {
                        Task { await model.setAudio(emby, st.Index) }
                    }
                }
                Divider().padding(.horizontal, 18).padding(.vertical, 4)
            }
            Text("Quality").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).padding(.horizontal, 22).padding(.top, 4)
            ForEach([(0, "Original"), (8_000_000, "1080p · 8 Mbps"), (4_000_000, "720p · 4 Mbps"), (1_500_000, "480p · 1.5 Mbps")], id: \.0) { q in
                row("dial.medium", q.1, checked: model.quality == q.0) { Task { await model.setQuality(emby, q.0) } }
            }
        }
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
struct AVPlayerViewRep: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.allowsPictureInPicturePlayback = false
        v.allowsVideoFrameAnalysis = false
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}
