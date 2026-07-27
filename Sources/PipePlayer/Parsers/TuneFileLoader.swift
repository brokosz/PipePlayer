import Foundation

enum TuneFileLoaderError: Error, LocalizedError {
    case unsupportedExtension(String)
    case unreadableEncoding

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let ext):
            return "\"\(ext)\" isn't a supported file type — PipePlayer opens .abc, .bww, and .bmw files."
        case .unreadableEncoding:
            return "Couldn't read this file as text — it may be corrupted."
        }
    }
}

/// Routes a file to the right parser by extension, since `.bww` and `.bmw`
/// share the same tune-code grammar (see BWWParser) and `.abc` uses its own.
enum TuneFileLoader {

    static func load(from url: URL) throws -> Tune {
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw TuneFileLoaderError.unreadableEncoding
        }

        switch ext {
        case "abc":
            return try ABCParser.parse(text)
        case "bww", "bmw":
            return try BWWParser.parse(text)
        default:
            throw TuneFileLoaderError.unsupportedExtension(ext.isEmpty ? url.lastPathComponent : ext)
        }
    }

    static let supportedExtensions = ["abc", "bww", "bmw"]
}
