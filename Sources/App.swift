import SwiftUI
import AppKit

@main
struct EmbyFlixApp: App {
    @StateObject private var emby = Emby()
    @AppStorage("accent") private var accent = "red"
    @AppStorage("bg") private var bg = "black"
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
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
