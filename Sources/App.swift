import SwiftUI
import AppKit

@main
struct EmbyFlixApp: App {
    @StateObject private var emby = Emby()
    @AppStorage("accent") private var accent = "red"
    @AppStorage("bg") private var bg = "black"
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        // In EmbyFlix.app the icon comes from Info.plist. When run from `swift run`, load it from the
        // SwiftPM resource bundle next to the binary. (Bundle.module crashes if that bundle is missing.)
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil,
           let res = Bundle.main.url(forResource: "EmbyFlix_EmbyFlix", withExtension: "bundle"),
           let url = Bundle(url: res)?.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = img
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(emby)
                .environment(\.appBG, Theme.bg(bg))
                .tint(Theme.accent(accent))
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 650)
                .task { await Updater.shared.checkOnLaunch() }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await Updater.shared.check(interactive: true) } }
            }
        }
    }
}

/// "v0.5Beta" style version from the app bundle (set by make-app.sh), or "dev" when run from Xcode / swift run.
enum AppVersion {
    static var label: String {
        let i = Bundle.main.infoDictionary
        if let v = i?["EmbyFlixVersion"] as? String, !v.isEmpty { return pretty(v) }
        return "dev"
    }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
    /// "v0.4Beta" -> "v0.4 Beta"
    static func pretty(_ v: String) -> String {
        v.replacingOccurrences(of: #"(\d)(Beta|Alpha|RC)"#, with: "$1 $2", options: .regularExpression)
    }
}
