import SwiftUI

@main
struct PipePlayerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .onOpenURL { url in
                    // Finder's "Open With"/double-click and the custom
                    // document-type registrations in package_app.sh's
                    // Info.plist deliver the file here — without this,
                    // Launch Services still launches/activates the app and
                    // opens a window, but nothing ever reads the file.
                    appState.open(url: url)
                }
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
