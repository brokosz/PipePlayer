import Foundation

enum TuneFileLoaderError: Error, LocalizedError {
    case unsupportedExtension(String)
    case unreadableEncoding

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let ext):
            return "\"\(ext)\" isn't a supported file type — PipePlayer opens .abc, .bww, .bmw, .musicxml/.xml, and .mxl files."
        case .unreadableEncoding:
            return "Couldn't read this file as text — it may be corrupted."
        }
    }
}

/// Routes a file to the right parser by extension. `.bww` and `.bmw` share
/// the same tune-code grammar (see `BWWParser`); `.abc` uses its own;
/// `.musicxml`/`.xml` and (compressed) `.mxl` both go through
/// `MusicXMLParser`, with `.mxl` first unwrapped by `MXLArchiveReader` since
/// it's a ZIP container, not plain text.
enum TuneFileLoader {

    /// Loads every simultaneous voice in the file. ABC and BWW/BMW are
    /// inherently monophonic, so they always produce exactly one voice
    /// ("Melody"); MusicXML can produce several, one per `<part>`, for a
    /// real harmony arrangement.
    static func loadVoices(from url: URL) throws -> [Voice] {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "mxl":
            let xmlData = try MXLArchiveReader.extractScoreXML(fromArchiveAt: url)
            return try MusicXMLParser.parseVoices(xmlData)
        case "xml", "musicxml":
            let data = try Data(contentsOf: url)
            return try MusicXMLParser.parseVoices(data)
        case "abc":
            return [Voice(id: "melody", name: "Melody", tune: try ABCParser.parse(try loadText(from: url)))]
        case "bww", "bmw":
            let tune = try BWWParser.parse(try loadText(from: url))
            let scaleFactor = BWWParser.tempoScaleFactor(forTimeSignature: tune.timeSignature)
            return [Voice(id: "melody", name: "Melody", tune: tune, displayTempoScaleFactor: scaleFactor)]
        default:
            throw TuneFileLoaderError.unsupportedExtension(ext.isEmpty ? url.lastPathComponent : ext)
        }
    }

    static func load(from url: URL) throws -> Tune {
        guard let first = try loadVoices(from: url).first else {
            throw MusicXMLParserError.noPartFound
        }
        return first.tune
    }

    private static func loadText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw TuneFileLoaderError.unreadableEncoding
        }
        return text
    }

    static let supportedExtensions = ["abc", "bww", "bmw", "musicxml", "xml", "mxl"]
}
