import Testing
import Foundation
@testable import PipePlayer

@MainActor
struct AppStateTests {

    private func writeTempTune() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bww")
        try """
        Bagpipe Music Writer Gold:1.0

        "Test",(T,L,10,10,Times New Roman,14,0)
        & sharpf sharpc 2_4 I!''
        ! LA_8 B_8 ''!I
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func openRecordsTheFileAndCloseClearsIt() throws {
        let url = try writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = AppState()

        state.open(url: url, addToRecents: false)
        #expect(state.currentURL == url)
        #expect(state.tune != nil)

        state.closeTune()
        #expect(state.currentURL == nil)
    }

    @Test func restoringATabDoesNotReshuffleRecents() throws {
        let url = try writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = AppState()
        let before = state.recentURLs

        state.open(url: url, addToRecents: false)
        #expect(state.recentURLs == before)
    }
}
