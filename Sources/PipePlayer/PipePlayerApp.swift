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
            appState?.presentOpenPanel()
        }
        .keyboardShortcut("o", modifiers: .command)
        .disabled(appState == nil)

        Menu("Open Recent") {
            if let appState, !appState.recentURLs.isEmpty {
                ForEach(appState.recentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        appState.open(url: url)
                    }
                }
                Divider()
                Button("Clear Menu") {
                    appState.clearRecents()
                }
            } else {
                Button("No Recent Files") {}
                    .disabled(true)
            }
        }
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
