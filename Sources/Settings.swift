import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// App settings: one window with a sidebar of sections.
/// Values live in UserDefaults (the same keys the rest of the app reads).
struct SettingsView: View {
    @EnvironmentObject var emby: Emby
    @Environment(\.dismiss) var dismiss
    @Environment(\.appBG) var bg
    var onDone: () -> Void

    enum Section: String, CaseIterable, Identifiable {
        case general = "General", libraries = "Libraries",
             subtitles = "Subtitles", playback = "Playback", servers = "Servers", about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "paintpalette"
            case .libraries: return "square.grid.2x2"
            case .subtitles: return "captions.bubble"
            case .playback: return "play.rectangle"
            case .servers: return "server.rack"
            case .about: return "info.circle"
            }
        }
    }
    @State private var section: Section = .general

    var body: some View {
        VStack(spacing: 0) {
            // Apple TV style: the section name on top, then a row of icon tabs
            Text(section.rawValue).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                .padding(.top, 12)
            HStack(spacing: 4) {
                ForEach(Section.allCases) { s in
                    let on = section == s
                    Button { section = s } label: {
                        VStack(spacing: 3) {
                            Image(systemName: s.icon).font(.system(size: 20))
                            Text(s.rawValue).font(.system(size: 11))
                        }
                        .foregroundColor(on ? Color(red: 0.24, green: 0.56, blue: 1) : .secondary)
                        .frame(minWidth: 62).padding(.horizontal, 6).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.white.opacity(0.1) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.white.opacity(0.12) : Color.clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).focusEffectDisabled()
                }
            }.padding(.top, 8).padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .general: GeneralSettings()
                    case .libraries: LibrariesSettings()
                    case .subtitles: SubtitleSettings()
                    case .playback: PlaybackSettings()
                    case .servers: ServerSettings()
                    case .about: AboutSettings()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30).padding(.vertical, 10)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                Button { emby.saveLibs(); onDone(); dismiss() } label: { Text("OK").frame(minWidth: 60) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.2, green: 0.5, blue: 1)).controlSize(.large)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 760, height: 640)
        .background(Color(white: 0.13))
    }
}

// MARK: - Building blocks

/// A section like macOS / Apple TV settings: a right-aligned "Title:" label, the controls beside it,
/// and a thin line under it.
struct SettingsGroup<C: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title + ":").frame(width: 170, alignment: .trailing)
                VStack(alignment: .leading, spacing: 10) {
                    content
                    if let note { Text(note).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 16)
            Divider()
        }
    }
}

struct SettingRow<C: View>: View {
    let label: String
    @ViewBuilder var control: C
    var body: some View {
        HStack(spacing: 10) {
            Text(label).foregroundColor(.secondary)
            control
            Spacer(minLength: 0)
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
    @AppStorage("navStyle") private var navStyle = "sidebar"

    func swatches(_ list: [(String, Color)], selection: Binding<String>) -> some View {
        HStack(spacing: 14) {
            ForEach(list, id: \.0) { name, color in
                Button { selection.wrappedValue = name } label: {
                    Circle().fill(color).frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        // selection ring sits outside the swatch so it also shows on the white one
                        .overlay(Circle().stroke(Color.white, lineWidth: 3).padding(-5)
                            .opacity(selection.wrappedValue == name ? 1 : 0))
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
            SettingRow(label: "Navigation") {
                Picker("", selection: $navStyle) {
                    Text("Sidebar").tag("sidebar")
                    Text("Top bar").tag("topbar")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }.padding(.top, 4)
            Text("Top bar replaces the sidebar with a bar across the top (Home, Favorites, libraries and search). Settings are in the Cove menu (⌘,).")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - About

/// The last section: app name, version, updates and source link, then Reset.
struct AboutSettings: View {
    @EnvironmentObject var emby: Emby
    @State private var confirmReset = false
    @State private var backupMessage: String?

    /// Saved servers and sign-ins: kept by Reset, and never written to or read from a settings file.
    static let keep: Set<String> = ["server", "token", "uid", "servers", "did", "importedEmbyFlix"]

    /// Forgets every saved preference (colors, layout, filters, hover, subtitle and player settings, library
    /// order and window positions). The saved servers and sign-ins are kept.
    func resetAllSettings() {
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys where !Self.keep.contains(key) {
            d.removeObject(forKey: key)
        }
        Task { await emby.loadLibs() }
    }

    /// The app's own preferences (not the system-wide ones UserDefaults also reports), without servers and sign-ins.
    var ownSettings: [String: Any] {
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        return (UserDefaults.standard.persistentDomain(forName: domain) ?? [:]).filter { !Self.keep.contains($0.key) }
    }

    /// Writes the settings to a property list file the user picks.
    func saveSettings() {
        let panel = NSSavePanel()
        panel.title = "Save Settings"
        panel.nameFieldStringValue = "Cove Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: ownSettings, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            backupMessage = "Settings saved to \(url.lastPathComponent)."
        } catch {
            backupMessage = "Couldn't save the settings: \(error.localizedDescription)"
        }
    }

    /// Replaces the current settings with the ones in a file saved earlier. Servers and sign-ins stay as they are.
    func loadSettings() {
        let panel = NSOpenPanel()
        panel.title = "Load Settings"
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let loaded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                backupMessage = "That file doesn't contain settings."; return
            }
            let d = UserDefaults.standard
            for key in ownSettings.keys { d.removeObject(forKey: key) }
            for (key, value) in loaded where !Self.keep.contains(key) { d.set(value, forKey: key) }
            Task { await emby.loadLibs() }
            backupMessage = "Settings loaded. Quit and reopen the app so the window and player pick up every change."
        } catch {
            backupMessage = "Couldn't load the settings: \(error.localizedDescription)"
        }
    }

    var body: some View {
        SettingsGroup(title: "About") {
            SettingRow(label: "App") { Text("Cove").foregroundColor(.secondary) }
            SettingRow(label: "Version") {
                Text(AppVersion.label)
                    .foregroundColor(.secondary).textSelection(.enabled)
            }
            SettingRow(label: "Updates") { UpdateRow() }
            SettingRow(label: "Source & releases") {
                Link("github.com/J0n4e/Embyfix", destination: URL(string: "https://github.com/J0n4e/Embyfix/releases")!)
            }
        }
        SettingsGroup(title: "Save and load settings",
                      note: "Saves every setting to a file you choose, and loads them back later or on another Mac. Your servers and sign-in are not included.") {
            HStack(spacing: 10) {
                Button("Save settings…") { saveSettings() }
                Button("Load settings…") { loadSettings() }
            }
        }
        .alert(backupMessage ?? "", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        SettingsGroup(title: "Reset",
                      note: "Puts every setting back to its default: colors, navigation, layouts, filters, hover preview, subtitles, player and window position. Your servers and sign-in are kept.") {
            Button("Reset all settings to default…", role: .destructive) { confirmReset = true }
        }
        .alert("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { resetAllSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything goes back to its default. You stay signed in. Quit and reopen the app afterwards so the window starts fresh.")
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
    @AppStorage("showEpisodeDescription") private var showEpDesc = true
    @AppStorage("episodeLayoutTV") private var epLayout = "row"
    @AppStorage("hoverPreviewEnabled") private var hoverOn = true
    @AppStorage("hoverPreviewDelay") private var hoverDelay = 0.7
    @AppStorage("hoverZoomEnabled") private var hoverZoom = true
    @AppStorage("hoverZoomDuration") private var hoverZoomDur = 0.3
    @AppStorage("hoverZoomStyle") private var hoverZoomStyle = "spring"
    @State private var tick = 0   // redraw after writing per-library defaults

    func bind(_ lib: LibPref, _ k: String, _ def: String) -> Binding<String> {
        let d = LibraryDefaults(id: lib.id)
        return Binding(get: { _ = tick; return d.get(k, def) }, set: { d.set(k, $0); tick += 1 })
    }

    var body: some View {
        SettingsGroup(title: "New libraries") {
            SettingRow(label: "Layout") { segmented($defaultLayout, [("grid", "Grid"), ("list", "List")]) }
        }
        SettingsGroup(title: "Poster labels") {
            Toggle("Show title under posters", isOn: $showTitle)
            Toggle("Show year under posters", isOn: $showYear)
            SettingRow(label: "Alignment") { segmented($labelAlign, [("center", "Centered"), ("left", "Left")]) }
                .disabled(!showTitle && !showYear)
        }
        SettingsGroup(title: "Series") {
            SettingRow(label: "Episode layout") { segmented($epLayout, [("row", "Row"), ("grid", "Grid"), ("list", "List")]) }
            Toggle("Show episode description", isOn: $showEpDesc)
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
            FlowLayout(hSpacing: 18, vSpacing: 8) {
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
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func labeled<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 6) { Text(t).foregroundColor(.secondary).lineLimit(1).fixedSize(); c() }.fixedSize()
    }
}

// MARK: - Series & episodes

struct SeriesSettings: View {
    @AppStorage("episodeLayoutTV") private var epLayout = "row"
    @AppStorage("episodeSubLang") private var epSubLang = ""

    static let languages = ["English", "Romanian", "Spanish", "French", "German", "Italian", "Portuguese",
                            "Dutch", "Hungarian", "Polish", "Russian", "Turkish", "Greek", "Swedish",
                            "Norwegian", "Danish", "Finnish", "Czech", "Arabic", "Hebrew", "Japanese",
                            "Korean", "Chinese"]

    var langOptions: [(String, String)] {
        let always = UserDefaults.standard.bool(forKey: "subAlways")
        var list = [("", always ? (UserDefaults.standard.string(forKey: "subLang") ?? "english").capitalized : "Off")] + (always ? [("off", "Off")] : [])
            + Self.languages.map { ($0.lowercased(), $0) }
        if !epSubLang.isEmpty, !list.contains(where: { $0.0 == epSubLang }) {
            list.append((epSubLang, epSubLang.capitalized))
        }
        return list
    }

    var body: some View {
        SettingsGroup(title: "Episodes") {
            SettingRow(label: "Episode layout") { segmented($epLayout, [("row", "Row"), ("grid", "Grid"), ("list", "List")]) }
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
        SettingsGroup(title: "Account") {
            if let user = emby.currentServer?.user, !user.isEmpty {
                SettingRow(label: "User") { Text(user).foregroundColor(.secondary).textSelection(.enabled) }
            }
            SettingRow(label: "Signed in to \(emby.currentServerName)") {
                Button("Sign Out", role: .destructive) { emby.logout() }
            }
        }
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
