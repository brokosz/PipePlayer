import SwiftUI

@main
struct PipePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        ExternalOpens.markLaunched()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        // Files from Finder go to `AppDelegate` and are routed by
        // `ExternalOpens`; matching nothing here stops SwiftUI from also
        // making a window of its own for each one.
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .newItem) {
                AppMenuCommands()
            }
            CommandGroup(after: .newItem) {
                Divider()
                CloseTuneMenuCommand()
            }
        }
    }
}

/// Commands live at the `Scene` level, outside any single window's view
/// hierarchy, so they can't just hold a reference to "the" `AppState` now
/// that every window/tab owns its own — `@FocusedObject` (published by
/// `ContentView`'s `.focusedSceneObject(appState)`) is what tells a menu
/// command which window's state to act on.
private struct AppMenuCommands: View {
    @FocusedObject private var appState: AppState?
    @ObservedObject private var recents = RecentTunes.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Hands the window opener to `ExternalOpens`, which runs outside any
        // view and needs it when a file arrives with no window open.
        let _ = (ExternalOpens.openWindow = { [openWindow] in openWindow(id: "main") })

        Button("New Window") {
            openWindow(id: "main")
        }
        .keyboardShortcut("n", modifiers: .command)

        Button("New Set") {
            if let appState, appState.isEmptyTab {
                appState.newSet()
            } else {
                PendingTuneOpens.shared.enqueueNewSet()
                openWindow(id: "main")
            }
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

        Button("Open…") {
            AppState.chooseTuneFiles().forEach(open)
        }
        .keyboardShortcut("o", modifiers: .command)

        Button("Add Harmony…") {
            guard let appState else { return }
            appState.addHarmony(urls: AppState.chooseTuneFiles())
        }
        .keyboardShortcut("o", modifiers: [.command, .option])
        .disabled(appState.map { $0.tune == nil && !($0.isSet && !$0.engine.segments.isEmpty) } ?? true)

        Button("Save Set…") {
            appState?.chooseLocationAndSaveSet()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(appState?.isSet != true || appState?.currentURL != nil)

        Button("Make Set") {
            appState?.makeSet()
        }
        .disabled(appState?.tune == nil || appState?.isSet == true)

        Button("Save as Set…") {
            appState?.chooseLocationAndSaveTuneAsSet()
        }
        .disabled(appState?.tune == nil || appState?.isSet == true)

        Menu("Open Recent") {
            if recents.urls.isEmpty {
                Button("No Recent Files") {}
                    .disabled(true)
            } else {
                ForEach(recents.urls, id: \.self) { url in
                    Button(url.lastPathComponent) { open(url) }
                }
                Divider()
                Button("Clear Menu") { recents.clear() }
            }
        }
    }

    /// With no window open there's no AppState to load into, so
    /// `TuneOpener` opens a window for the file — it picks the URL up on
    /// appear.
    private func open(_ url: URL) {
        TuneOpener.open(url, from: appState) { openWindow(id: "main") }
    }
}

private struct CloseTuneMenuCommand: View {
    @FocusedObject private var appState: AppState?

    var body: some View {
        Button("Close Tune") {
            appState?.closeTune()
        }
        .disabled(appState?.tune == nil)
    }
}

/// Receives files opened from Finder (double-click, Open With, drag onto
/// the Dock icon). SwiftUI's own routing of these raced tab restoration on
/// launch and, with every window closed, delivered them to no window at all.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { ExternalOpens.receive(urls) }
    }
}

/// Routes files from Finder the same way File → Open does (`TuneOpener`):
/// the tab already showing it, else an empty tab, else a new tab — opening
/// a window when none is open.
@MainActor
enum ExternalOpens {
    static var openWindow: (() -> Void)?
    private static var launchedAt = Date()

    static func markLaunched() { launchedAt = Date() }

    static func receive(_ urls: [URL]) {
        whenTabsRestored {
            NSApp?.activate(ignoringOtherApps: true)
            for url in urls {
                TuneOpener.open(url, from: OpenTabs.shared.firstEmptyTab) { openWindow?() }
            }
        }
    }

    /// At launch, waits until restored tabs have their tunes back before
    /// routing: SceneStorage delivers them a beat after the window appears
    /// (measured at over a second for a tab group), and a file routed sooner
    /// can land in a restored tab and replace its tune. Ready once every tab
    /// holds something, or after 3 seconds (a fresh, empty window never
    /// fills on its own). Later opens go straight through.
    private static func whenTabsRestored(_ action: @escaping @MainActor () -> Void) {
        let elapsed = Date().timeIntervalSince(launchedAt)
        let settled = elapsed > 0.3 && OpenTabs.shared.hasTabs && OpenTabs.shared.firstEmptyTab == nil
        if elapsed >= 3 || settled {
            action()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                MainActor.assumeIsolated { whenTabsRestored(action) }
            }
        }
    }
}
