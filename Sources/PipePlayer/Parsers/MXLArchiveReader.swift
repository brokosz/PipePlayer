import Foundation

enum MXLArchiveReaderError: Error, LocalizedError {
    case unzipFailed(String)
    case missingContainer
    case malformedContainer

    var errorDescription: String? {
        switch self {
        case .unzipFailed(let detail):
            return "Couldn't open this .mxl file: \(detail)"
        case .missingContainer:
            return "This .mxl file is missing its META-INF/container.xml — it doesn't look like a valid compressed MusicXML archive."
        case .malformedContainer:
            return "Couldn't find the score file referenced by this .mxl archive's container.xml."
        }
    }
}

/// Extracts the actual MusicXML score `Data` out of a compressed `.mxl`
/// archive. `.mxl` is a plain ZIP container: `META-INF/container.xml` names
/// the path of the real score file inside via a `<rootfile full-path="...">`
/// attribute. Shells out to the system's `unzip` (present on every Mac)
/// rather than pulling in a third-party ZIP library — this project has no
/// external dependencies and a single-purpose "read one named entry from a
/// zip" doesn't need one either.
enum MXLArchiveReader {

    static func extractScoreXML(fromArchiveAt url: URL) throws -> Data {
        let containerData = try runUnzip(archivePath: url.path, entryPath: "META-INF/container.xml")
        guard let containerXML = String(data: containerData, encoding: .utf8), !containerXML.isEmpty else {
            throw MXLArchiveReaderError.missingContainer
        }
        guard let rootFilePath = firstRootFilePath(in: containerXML) else {
            throw MXLArchiveReaderError.malformedContainer
        }
        return try runUnzip(archivePath: url.path, entryPath: rootFilePath)
    }

    /// Pulls the first `<rootfile full-path="...">` attribute out of
    /// container.xml with a small manual scan rather than a full XML parse
    /// — container.xml is a tiny, fixed-shape file, not worth the ceremony.
    private static func firstRootFilePath(in containerXML: String) -> String? {
        guard let tagRange = containerXML.range(of: "<rootfile") else { return nil }
        let afterTag = containerXML[tagRange.upperBound...]
        guard let attrRange = afterTag.range(of: "full-path=\"") else { return nil }
        let afterAttr = afterTag[attrRange.upperBound...]
        guard let closingQuote = afterAttr.firstIndex(of: "\"") else { return nil }
        return String(afterAttr[afterAttr.startIndex..<closingQuote])
    }

    private static func runUnzip(archivePath: String, entryPath: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archivePath, entryPath]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw MXLArchiveReaderError.unzipFailed(error.localizedDescription)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "unzip exited with status \(process.terminationStatus)"
            throw MXLArchiveReaderError.unzipFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outputData
    }
}
