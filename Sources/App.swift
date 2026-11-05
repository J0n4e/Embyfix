import SwiftUI
import AppKit

@main
struct CoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var emby = Emby()
    @AppStorage("accent") private var accent = "red"
    @AppStorage("bg") private var bg = "black"
    init() {
        Self.importEmbyFlixSettings()
        NSApplication.shared.setActivationPolicy(.regular)
        // In the built app the icon comes from Info.plist. When run from `swift run`, load it from the
        // SwiftPM resource bundle next to the binary. (Bundle.module crashes if that bundle is missing.)
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil,
           let res = Bundle.main.url(forResource: "Cove_Cove", withExtension: "bundle"),
           let url = Bundle(url: res)?.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = img
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    /// Cove used to be EmbyFlix, a separate app with its own preferences. The first time Cove starts it copies
    /// those over (settings, saved servers and sign-ins), so nobody has to set it up again.
    static func importEmbyFlixSettings() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "importedEmbyFlix") else { return }
        d.set(true, forKey: "importedEmbyFlix")
        guard let old = d.persistentDomain(forName: "EmbyFlix"), !old.isEmpty else { return }
        for (key, value) in old where d.object(forKey: key) == nil { d.set(value, forKey: key) }
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
        if let v = i?["CoveVersion"] as? String, !v.isEmpty { return pretty(v) }
        return "dev"
    }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
    /// "v0.4Beta" -> "v0.4 Beta"
    static func pretty(_ v: String) -> String {
        v.replacingOccurrences(of: #"(\d)(Beta|Alpha|RC)"#, with: "$1 $2", options: .regularExpression)
    }
}

/// Closing the window quits the app. Otherwise it kept running with no window, and clicking the Dock
/// icon didn't bring a window back.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
