import SwiftUI

@main
struct PipePlayerApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: "main")
        }
        .keyboardShortcut("n", modifiers: .command)

        Button("Open…") {
            if let appState {
                appState.presentOpenPanel()
            } else if let url = AppState.chooseTuneFile() {
                openInNewWindow(url)
            }
        }
        .keyboardShortcut("o", modifiers: .command)

        Menu("Open Recent") {
            let recents = appState?.recentURLs ?? AppState.storedRecentURLs()
            if recents.isEmpty {
                Button("No Recent Files") {}
                    .disabled(true)
            } else {
                ForEach(recents, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        if let appState {
                            appState.open(url: url)
                        } else {
                            openInNewWindow(url)
                        }
                    }
                }
                Divider()
                Button("Clear Menu") {
                    if let appState {
                        appState.clearRecents()
                    } else {
                        AppState.clearStoredRecents()
                    }
                }
            }
        }
    }

    /// With no window open there's no AppState to load into, so open a
    /// window for the file — it picks the URL up on appear.
    private func openInNewWindow(_ url: URL) {
        PendingTuneOpens.shared.enqueue(url)
        openWindow(id: "main")
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
