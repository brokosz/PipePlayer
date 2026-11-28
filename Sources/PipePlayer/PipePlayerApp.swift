import SwiftUI

@main
struct PipePlayerApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        // By default a WindowGroup opens a brand-new window for every file
        // Finder hands it, before any code sees the URL — so reopening an
        // already-open tune left an empty tab behind. Matching nothing here
        // sends the URL to an existing window's `onOpenURL` instead, and
        // `TuneOpener` decides where it really goes. With no window open,
        // SwiftUI still makes one.
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
        .disabled(appState?.tune == nil || appState?.isSet == true)

        Button("Save Set…") {
            appState?.chooseLocationAndSaveSet()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(appState?.isSet != true || appState?.currentURL != nil)

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
