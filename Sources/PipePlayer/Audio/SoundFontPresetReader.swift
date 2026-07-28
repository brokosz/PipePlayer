import Foundation

/// One preset (aka "patch"/"program") found in a SoundFont (.sf2) file's
/// `phdr` chunk — e.g. `{ name: "Great Highland Bagpipe", program: 0, bank: 0 }`.
struct SoundFontPreset: Equatable {
    let name: String
    let program: Int
    let bank: Int
}

/// Reads just enough of a .sf2 file's RIFF structure to list its presets by
/// name, so the instrument picker can show "Great Highland Bagpipe" /
/// "Scottish Smallpipes" instead of the full 128-entry General MIDI list when
/// a custom SoundFont is loaded. Returns `[]` for anything that isn't a
/// well-formed SF2 (e.g. a .dls file, which uses a different chunk layout) —
/// callers should fall back to the GM name list in that case.
enum SoundFontPresetReader {
    static func presets(at url: URL) -> [SoundFontPreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let phdrData = findPhdrChunk(in: data) else { return [] }
        return parsePhdr(phdrData)
    }

    // MARK: - RIFF walking

    /// Top-level chunks are `RIFF <size> sfbk (LIST <size> INFO ...)(LIST <size> sdta ...)(LIST <size> pdta ...)`.
    /// We only need to descend into the `pdta` LIST to find `phdr`.
    private static func findPhdrChunk(in data: Data) -> Data? {
        guard data.count > 12,
              data[data.startIndex..<data.startIndex+4].elementsEqual(Array("RIFF".utf8)) else { return nil }
        let riffBody = data.subdata(in: (data.startIndex + 12)..<data.endIndex) // skip "RIFF"+size+"sfbk"
        var offset = riffBody.startIndex
        while offset + 8 <= riffBody.endIndex {
            let cid = String(decoding: riffBody[offset..<offset+4], as: UTF8.self)
            let size = Int(readUInt32LE(riffBody, at: offset + 4))
            let contentStart = offset + 8
            guard contentStart + size <= riffBody.endIndex else { break }
            let content = riffBody.subdata(in: contentStart..<contentStart + size)
            if cid == "LIST", content.count >= 4 {
                let listType = String(decoding: content[content.startIndex..<content.startIndex+4], as: UTF8.self)
                if listType == "pdta" {
                    return findSubChunk("phdr", in: content.subdata(in: (content.startIndex + 4)..<content.endIndex))
                }
            }
            offset = contentStart + size + (size % 2) // chunks are word-aligned
        }
        return nil
    }

    private static func findSubChunk(_ target: String, in data: Data) -> Data? {
        var offset = data.startIndex
        while offset + 8 <= data.endIndex {
            let cid = String(decoding: data[offset..<offset+4], as: UTF8.self)
            let size = Int(readUInt32LE(data, at: offset + 4))
            let contentStart = offset + 8
            guard contentStart + size <= data.endIndex else { break }
            if cid == target {
                return data.subdata(in: contentStart..<contentStart + size)
            }
            offset = contentStart + size + (size % 2)
        }
        return nil
    }

    // MARK: - phdr record parsing

    /// Each `phdr` record is a fixed 38 bytes: 20-byte name, uint16 preset,
    /// uint16 bank, uint16 presetBagNdx, uint32 library/genre/morphology
    /// (unused here). The file always ends with a terminal "EOP" record,
    /// which we drop.
    private static func parsePhdr(_ data: Data) -> [SoundFontPreset] {
        let recordSize = 38
        var presets: [SoundFontPreset] = []
        var offset = data.startIndex
        while offset + recordSize <= data.endIndex {
            let nameData = data.subdata(in: offset..<offset+20)
            let name = decodeCString(nameData)
            let program = Int(readUInt16LE(data, at: offset + 20))
            let bank = Int(readUInt16LE(data, at: offset + 22))
            if name != "EOP" && !name.isEmpty {
                presets.append(SoundFontPreset(name: name, program: program, bank: bank))
            }
            offset += recordSize
        }
        return presets.sorted { ($0.bank, $0.program) < ($1.bank, $1.program) }
    }

    private static func decodeCString(_ data: Data) -> String {
        let bytes = data.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func readUInt32LE(_ data: Data, at index: Data.Index) -> UInt32 {
        let b0 = UInt32(data[index])
        let b1 = UInt32(data[index+1])
        let b2 = UInt32(data[index+2])
        let b3 = UInt32(data[index+3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    private static func readUInt16LE(_ data: Data, at index: Data.Index) -> UInt16 {
        let b0 = UInt16(data[index])
        let b1 = UInt16(data[index+1])
        return b0 | (b1 << 8)
    }
}
