import Foundation
import AppKit

/// Decides where a file the user asked to open should go. Every open path
/// — File → Open, Open Recent, drag and drop, Finder — goes through here so
/// they all behave the same:
///
/// 1. Already open in some tab → bring that tab forward. No duplicates.
/// 2. The tab it came from is empty → load it there.
/// 3. Otherwise → a new tab. A loaded tune is never replaced out from under
///    the user; Close Tune is how to empty a tab on purpose.
///
/// "New tab" is `openWindow`, which becomes a tab or a window according to
/// the system's Prefer Tabs setting.
@MainActor
enum TuneOpener {
    static func open(_ url: URL, from target: AppState?, newTab: () -> Void) {
        if let existing = OpenTabs.shared.tab(showing: url) {
            existing.bringToFront()
            existing.recents.add(url)
            return
        }
        if let target, target.tune == nil {
            target.open(url: url)
            return
        }
        PendingTuneOpens.shared.enqueue(url)
        newTab()
    }
}

/// Every live tab's `AppState`, so an open can find a tab already showing
/// the file. Held weakly — a closed tab drops out on its own.
@MainActor
final class OpenTabs {
    static let shared = OpenTabs()

    private struct WeakRef { weak var state: AppState? }
    private var refs: [WeakRef] = []

    func register(_ state: AppState) {
        refs.removeAll { $0.state == nil }
        refs.append(WeakRef(state: state))
    }

    func tab(showing url: URL) -> AppState? {
        refs.removeAll { $0.state == nil }
        return refs.lazy.compactMap(\.state).first { state in
            state.currentURL.map { $0.isSameFile(as: url) } ?? false
        }
    }
}

/// Files waiting for the tab opened for them to claim one. SwiftUI's
/// `openWindow(id:)` can't hand a value to the new window directly (that
/// would need a value-typed `WindowGroup`), so the opener parks the URL
/// here and the new tab's `ContentView` takes it on appear.
@MainActor
final class PendingTuneOpens {
    static let shared = PendingTuneOpens()
    private var urls: [URL] = []

    func enqueue(_ url: URL) { urls.append(url) }

    func takeNext() -> URL? {
        urls.isEmpty ? nil : urls.removeFirst()
    }
}
