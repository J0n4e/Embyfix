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
        }
    }
}
