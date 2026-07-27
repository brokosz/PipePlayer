import SwiftUI

@main
struct PipePlayerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    appState.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    if appState.recentURLs.isEmpty {
                        Button("No Recent Files") {}
                            .disabled(true)
                    } else {
                        ForEach(appState.recentURLs, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                appState.open(url: url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            appState.clearRecents()
                        }
                    }
                }
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Close Tune") {
                    appState.closeTune()
                }
                .disabled(appState.tune == nil)
            }
        }
    }
}
