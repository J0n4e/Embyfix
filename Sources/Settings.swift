import SwiftUI

/// App settings: one window with a sidebar of sections.
/// Values live in UserDefaults (the same keys the rest of the app reads).
struct SettingsView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.dismiss) var dismiss
    var onDone: () -> Void

    enum Section: String, CaseIterable, Identifiable {
        case general = "General", libraries = "Libraries", series = "Series & Episodes",
             subtitles = "Subtitles", playback = "Playback", servers = "Servers"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "paintpalette"
            case .libraries: return "square.grid.2x2"
            case .series: return "tv"
            case .subtitles: return "captions.bubble"
            case .playback: return "play.rectangle"
            case .servers: return "server.rack"
            }
        }
    }
    @State private var section: Section = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.title2.bold())
                Spacer()
                Button("Done") { emby.saveLibs(); onDone(); dismiss() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }.padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Section.allCases) { s in
                        Button { section = s } label: {
                            Label(s.rawValue, systemImage: s.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(section == s ? Color.white.opacity(0.14) : Color.clear)
                                .cornerRadius(6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 190).padding(10)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch section {
                        case .general: GeneralSettings()
                        case .libraries: LibrariesSettings()
                        case .series: SeriesSettings()
                        case .subtitles: SubtitleSettings()
                        case .playback: PlaybackSettings()
                        case .servers: ServerSettings()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
            }
        }
        .frame(width: 860, height: 580)
    }
}

// MARK: - Building blocks

struct SettingsGroup<C: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06)).cornerRadius(8)
            if let note { Text(note).font(.caption).foregroundColor(.secondary) }
        }
    }
}

struct SettingRow<C: View>: View {
    let label: String
    @ViewBuilder var control: C
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            control
        }
    }
}

func segmented<T: Hashable>(_ sel: Binding<T>, _ opts: [(T, String)]) -> some View {
    Picker("", selection: sel) {
        ForEach(opts, id: \.0) { Text($0.1).tag($0.0) }
    }.pickerStyle(.segmented).labelsHidden().fixedSize()
}

func menuPicker<T: Hashable>(_ sel: Binding<T>, _ opts: [(T, String)]) -> some View {
    Picker("", selection: sel) {
        ForEach(opts, id: \.0) { Text($0.1).tag($0.0) }
    }.labelsHidden().fixedSize()
}

// MARK: - General

struct GeneralSettings: View {
    @AppStorage("accent") private var accent = "red"
    @AppStorage("bg") private var bg = "black"

    func swatches(_ list: [(String, Color)], selection: Binding<String>) -> some View {
        HStack(spacing: 14) {
            ForEach(list, id: \.0) { name, color in
                Button { selection.wrappedValue = name } label: {
                    Circle().fill(color).frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.white, lineWidth: selection.wrappedValue == name ? 3 : 0))
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .frame(width: 44, height: 44).contentShape(Circle())
                }.buttonStyle(.plain).help(name.capitalized)
            }
        }
    }

    /// Background picker: labelled tiles, the selected one ringed in the accent color.
    func bgTiles(selection: Binding<String>) -> some View {
        HStack(spacing: 12) {
            ForEach(Theme.backgrounds, id: \.0) { name, color in
                let on = selection.wrappedValue == name
                Button { selection.wrappedValue = name } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8).fill(color).frame(width: 64, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(on ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.15)), lineWidth: on ? 3 : 1))
                        Text(name.capitalized).font(.caption).foregroundColor(on ? .primary : .secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        SettingsGroup(title: "Appearance") {
            Text("Accent color").foregroundColor(.secondary)
            swatches(Theme.accents, selection: $accent)
            Text("Background").foregroundColor(.secondary).padding(.top, 4)
            bgTiles(selection: $bg)
        }
        SettingsGroup(title: "About") {
            SettingRow(label: "Version") {
                Text(AppVersion.build.isEmpty ? AppVersion.label : "\(AppVersion.label) (build \(AppVersion.build))")
                    .foregroundColor(.secondary).textSelection(.enabled)
            }
            SettingRow(label: "Updates") { UpdateRow() }
            SettingRow(label: "Source & releases") {
                Link("github.com/J0n4e/Embyfix", destination: URL(string: "https://github.com/J0n4e/Embyfix/releases")!)
            }
        }
    }
}

// MARK: - Libraries

/// Per-library view defaults, stored in the same "lf-<id>" dictionary the library page uses.
struct LibraryDefaults {
    let id: String
    var key: String { "lf-" + id }
    func get(_ k: String, _ def: String) -> String {
        (UserDefaults.standard.dictionary(forKey: key)?[k] as? String) ?? def
    }
    func set(_ k: String, _ v: Any) {
        var d = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        d[k] = v
        if k == "sort" { d["desc"] = (v as? String) != "name" }
        UserDefaults.standard.set(d, forKey: key)
    }
}

struct LibrariesSettings: View {
    @EnvironmentObject var emby: Emby
    @AppStorage("defaultLibraryLayout") private var defaultLayout = "grid"
    @AppStorage("posterShowTitle") private var showTitle = true
    @AppStorage("posterShowYear") private var showYear = true
    @AppStorage("posterLabelAlign") private var labelAlign = "center"
    @State private var tick = 0   // redraw after writing per-library defaults

    func bind(_ lib: LibPref, _ k: String, _ def: String) -> Binding<String> {
        let d = LibraryDefaults(id: lib.id)
        return Binding(get: { _ = tick; return d.get(k, def) }, set: { d.set(k, $0); tick += 1 })
    }

    var body: some View {
        SettingsGroup(title: "Default view for new libraries") {
            SettingRow(label: "Layout") { segmented($defaultLayout, [("grid", "Grid"), ("list", "List")]) }
        }
        SettingsGroup(title: "Poster labels") {
            Toggle("Show title under posters", isOn: $showTitle)
            Toggle("Show year under posters", isOn: $showYear)
            SettingRow(label: "Alignment") { segmented($labelAlign, [("center", "Centered"), ("left", "Left")]) }
                .disabled(!showTitle && !showYear)
        }
        SettingsGroup(title: "Libraries",
                      note: "Show puts a library in the sidebar; Home row adds it to the home screen. Use the arrows to reorder.") {
            if emby.libs.isEmpty { Text("No libraries loaded yet.").foregroundColor(.secondary) }
            ForEach(Array(emby.libs.enumerated()), id: \.element.id) { i, lib in
                libraryCard(i, lib)
                if i < emby.libs.count - 1 { Divider() }
            }
        }
        Button("Apply grid/list default to all libraries") {
            for lib in emby.libs { LibraryDefaults(id: lib.id).set("layout", defaultLayout) }
            tick += 1
        }
    }

    func libraryCard(_ i: Int, _ lib: LibPref) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField(lib.name, text: $emby.libs[i].title).textFieldStyle(.roundedBorder).frame(width: 200)
                Toggle("Show", isOn: $emby.libs[i].visible)
                Toggle("Home row", isOn: $emby.libs[i].onHome).disabled(!lib.visible)
                Spacer()
                Button { emby.libs.swapAt(i, i - 1) } label: { Image(systemName: "arrow.up") }
                    .disabled(i == 0).buttonStyle(.borderless)
                Button { emby.libs.swapAt(i, i + 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(i == emby.libs.count - 1).buttonStyle(.borderless)
            }
            HStack(spacing: 18) {
                labeled("View") { segmented(bind(lib, "layout", defaultLayout), [("grid", "Grid"), ("list", "List")]) }
                labeled("Sort") {
                    menuPicker(bind(lib, "sort", "name"),
                               [("name", "Name"), ("latest", "Recently Added"), ("release", "Release Date"), ("top", "Rating")])
                }
                labeled("Show") {
                    menuPicker(bind(lib, "watch", "all"), [("all", "All"), ("unwatched", "Unwatched"), ("watched", "Watched")])
                }
                labeled("Home row") {
                    menuPicker($emby.libs[i].style, [("latest", "Latest"), ("top", "Top Rated"), ("random", "Random"), ("az", "A–Z")])
                }.disabled(!lib.onHome || !lib.visible)
            }.font(.callout)
        }
    }

    func labeled<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 6) { Text(t).foregroundColor(.secondary); c() }
    }
}

// MARK: - Series & episodes

struct SeriesSettings: View {
    @AppStorage("episodeLayout") private var epLayout = "list"
    @AppStorage("episodeSubLang") private var epSubLang = ""

    static let languages = ["English", "Romanian", "Spanish", "French", "German", "Italian", "Portuguese",
                            "Dutch", "Hungarian", "Polish", "Russian", "Turkish", "Greek", "Swedish",
                            "Norwegian", "Danish", "Finnish", "Czech", "Arabic", "Hebrew", "Japanese",
                            "Korean", "Chinese"]

    var langOptions: [(String, String)] {
        var list = [("", "Off")] + Self.languages.map { ($0.lowercased(), $0) }
        if !epSubLang.isEmpty, !list.contains(where: { $0.0 == epSubLang }) {
            list.append((epSubLang, epSubLang.capitalized))
        }
        return list
    }

    var body: some View {
        SettingsGroup(title: "Episodes") {
            SettingRow(label: "Episode layout") { segmented($epLayout, [("grid", "Grid"), ("list", "List")]) }
            SettingRow(label: "Subtitle language") { menuPicker($epSubLang, langOptions) }
        }
        Text("The subtitle language is used for every episode you play from a series page; it's the same setting as the Subtitles menu next to the episode list.")
            .font(.caption).foregroundColor(.secondary)
    }
}

// MARK: - Subtitles

struct SubtitleSettings: View {
    @AppStorage("subTextSize") private var subTextSize = "normal"
    @AppStorage("subColor") private var subColor = "white"
    @AppStorage("subShadowStyle") private var subShadow = "drop"
    @AppStorage("subBg") private var subBg = "none"
    @AppStorage("subBottom") private var subBottom = 10.0
    @AppStorage("subAlways") private var subAlways = false
    @AppStorage("subLang") private var subLang = "english"

    var body: some View {
        SettingsGroup(title: "Subtitle language",
                      note: "When on, every movie and episode starts with subtitles in this language if it has them (text subtitles such as SRT are preferred). Choosing Off for a movie, or in the player, still turns them off.") {
            Toggle("Always load preferred subtitle language", isOn: $subAlways)
            SettingRow(label: "Preferred language") {
                menuPicker($subLang, SeriesSettings.languages.map { ($0.lowercased(), $0) })
            }.disabled(!subAlways)
        }
        SettingsGroup(title: "Subtitle appearance") {
            SettingRow(label: "Text size") { menuPicker($subTextSize, PlayerView.sizes.map { ($0.0, $0.1) }) }
            SettingRow(label: "Text color") { menuPicker($subColor, PlayerView.colors.map { ($0.0, $0.1) }) }
            SettingRow(label: "Drop shadow") { menuPicker($subShadow, PlayerView.shadows) }
            SettingRow(label: "Background") { menuPicker($subBg, PlayerView.bgs.map { ($0.0, $0.1) }) }
            SettingRow(label: "Bottom edge position") {
                menuPicker($subBottom, [0, 5, 10, 15, 20, 25, 30].map { (Double($0), "\($0)%") })
            }
        }
        preview
        Button("Reset to Default") {
            subTextSize = "normal"; subColor = "white"; subShadow = "drop"; subBg = "none"; subBottom = 10
        }
    }

    var preview: some View {
        let h: CGFloat = 220
        let fs = h * (PlayerView.sizes.first { $0.0 == subTextSize }?.2 ?? 0.045) * 1.6
        let color = PlayerView.colors.first { $0.0 == subColor }?.2 ?? .white
        return ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.4), Color(red: 0.75, green: 0.7, blue: 0.6)],
                           startPoint: .top, endPoint: .bottom)
            Text("This is how subtitles will look.")
                .font(.system(size: fs, weight: .medium))
                .foregroundColor(color)
                .modifier(SubShadow(style: subShadow, color: subColor == "black" ? .white : .black))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color.black.opacity(PlayerView.bgs.first { $0.0 == subBg }?.2 ?? 0))
                .cornerRadius(4)
                .padding(.bottom, h * subBottom / 100)
        }
        .frame(height: h).frame(maxWidth: .infinity).cornerRadius(8)
    }
}

// MARK: - Playback

struct PlaybackSettings: View {
    @AppStorage("defaultQuality") private var quality = 0
    @AppStorage("defaultSpeed") private var speed = 1.0
    @AppStorage("autoNext") private var autoNext = true
    @AppStorage("autoSkipIntro") private var autoSkipIntro = true
    @AppStorage("skipSeconds") private var skip = 10
    @AppStorage("clickToPause") private var clickToPause = true

    var body: some View {
        SettingsGroup(title: "Playback") {
            SettingRow(label: "Default quality") {
                menuPicker($quality, [(0, "Original"), (8_000_000, "1080p · 8 Mbps"), (4_000_000, "720p · 4 Mbps"), (1_500_000, "480p · 1.5 Mbps")])
            }
            SettingRow(label: "Default speed") {
                menuPicker($speed, [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map { ($0, $0 == 1 ? "Normal" : String(format: "%gx", $0)) })
            }
            SettingRow(label: "Skip back / forward") {
                segmented($skip, [(5, "5 s"), (10, "10 s"), (15, "15 s"), (30, "30 s")])
            }
            Toggle("Play next episode automatically", isOn: $autoNext)
            Toggle("Skip intros automatically", isOn: $autoSkipIntro)
            Toggle("Click on the video to play / pause", isOn: $clickToPause)
            Text("When off, clicking the video shows or hides the controls.").font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - Servers

struct ServerSettings: View {
    @EnvironmentObject var emby: Emby

    var body: some View {
        SettingsGroup(title: "Saved servers",
                      note: "Removing a server forgets its saved sign-in. You can add servers from the sign-in screen (Switch Server).") {
            if emby.servers.isEmpty { Text("No saved servers.").foregroundColor(.secondary) }
            ForEach(emby.servers) { s in
                HStack(spacing: 12) {
                    Image(systemName: "server.rack").frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(s.name).bold()
                            if s.id == emby.server.lowercased() {
                                Text("Current").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.6)))
                            }
                        }
                        Text(s.user.isEmpty ? s.url : "\(s.user) · \(s.url)").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(s.token != nil ? "Signed in" : "Signed out").font(.caption).foregroundColor(.secondary)
                    Button("Remove", role: .destructive) { emby.removeServer(s) }
                        .disabled(s.id == emby.server.lowercased())
                        .help(s.id == emby.server.lowercased() ? "Switch to another server first" : "")
                }
            }
        }
    }
}
