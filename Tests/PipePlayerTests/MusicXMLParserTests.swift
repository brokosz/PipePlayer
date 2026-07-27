import Testing
import Foundation
@testable import PipePlayer

struct MusicXMLParserTests {

    // Pitches chosen to land exactly on a chanter MIDI number (no
    // nearest-match ambiguity): G4=67(LowG), A4=69(LowA), C#5=73(C, the
    // chanter's fixed-sharp scale), D5=74(D).
    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.1">
      <work><work-title>Test Tune</work-title></work>
      <identification>
        <creator type="composer">Trad.</creator>
      </identification>
      <part-list>
        <score-part id="P1"><part-name>Chanter</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>4</divisions>
            <time><beats>2</beats><beat-type>4</beat-type></time>
          </attributes>
          <direction><sound tempo="90"/></direction>
          <barline location="left"><repeat direction="forward"/></barline>
          <note>
            <pitch><step>G</step><octave>4</octave></pitch>
            <duration>4</duration>
            <type>quarter</type>
          </note>
          <note>
            <pitch><step>A</step><octave>4</octave></pitch>
            <duration>4</duration>
            <type>quarter</type>
            <tie type="start"/>
          </note>
        </measure>
        <measure number="2">
          <note>
            <pitch><step>A</step><octave>4</octave></pitch>
            <duration>2</duration>
            <type>eighth</type>
            <tie type="stop"/>
          </note>
          <note>
            <grace/>
            <pitch><step>G</step><octave>5</octave></pitch>
          </note>
          <note>
            <pitch><step>C</step><octave>5</octave><alter>1</alter></pitch>
            <duration>2</duration>
            <type>eighth</type>
          </note>
          <barline location="right"><repeat direction="backward"/></barline>
        </measure>
      </part>
    </score-partwise>
    """

    @Test func headerFields() throws {
        let tune = try MusicXMLParser.parse(Data(sample.utf8))
        #expect(tune.title == "Test Tune")
        #expect(tune.composer == "Trad.")
        #expect(tune.timeSignature == "2/4")
        #expect(tune.tempo == 90)
    }

    @Test func repeatStructureAndMeasureGrouping() throws {
        let tune = try MusicXMLParser.parse(Data(sample.utf8))
        #expect(tune.parts.count == 1)
        #expect(tune.parts[0].hasRepeat == true)
        #expect(tune.parts[0].measures.count == 2)
    }

    @Test func pitchDurationAndTieMapping() throws {
        let tune = try MusicXMLParser.parse(Data(sample.utf8))
        let measure1 = tune.parts[0].measures[0].notes
        #expect(measure1.map(\.pitch) == [.lowG, .lowA])
        #expect(measure1.map(\.duration) == [1.0, 1.0])
        #expect(measure1[1].isTiedToNext == true)
        #expect(measure1[0].isTiedToNext == false)
    }

    @Test func graceNoteAndAlterMapping() throws {
        let tune = try MusicXMLParser.parse(Data(sample.utf8))
        let measure2 = tune.parts[0].measures[1].notes
        #expect(measure2.map(\.pitch) == [.lowA, .highG, .c])
        #expect(abs(measure2[0].duration - 0.5) < 0.0001)
        #expect(measure2[1].duration < 0.1) // grace note — short, borrowed time
        #expect(abs(measure2[2].duration - 0.5) < 0.0001)
    }

    @Test func compressedMXLRoundTrips() throws {
        // Build a real .mxl (zip) on the fly with the system `zip` tool and
        // confirm MXLArchiveReader + MusicXMLParser correctly extract and
        // parse the inner score, rather than only testing plain XML.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metaInfDir = tempDir.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaInfDir, withIntermediateDirectories: true)

        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container>
          <rootfiles>
            <rootfile full-path="score.xml" media-type="application/vnd.recordare.musicxml+xml"/>
          </rootfiles>
        </container>
        """
        try containerXML.write(to: metaInfDir.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)
        try sample.write(to: tempDir.appendingPathComponent("score.xml"), atomically: true, encoding: .utf8)

        let mxlURL = tempDir.appendingPathComponent("test.mxl")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.currentDirectoryURL = tempDir
        zipProcess.arguments = ["-r", "-q", mxlURL.path, "META-INF", "score.xml"]
        try zipProcess.run()
        zipProcess.waitUntilExit()
        #expect(zipProcess.terminationStatus == 0)

        let tune = try TuneFileLoader.load(from: mxlURL)
        #expect(tune.title == "Test Tune")
        #expect(tune.parts[0].hasRepeat == true)
    }

    @Test func emptyInputThrows() {
        #expect(throws: (any Error).self) { try MusicXMLParser.parse(Data()) }
    }

    @Test func bareLeftStyleAloneDoesNotIsolateAPickupMeasure() throws {
        // Real file found in the wild: a plain pickup measure's trailing
        // barline was tagged location="left" with bar-style "heavy-light" —
        // a common exporter quirk (the boundary *between* two measures
        // tagged on the earlier one's trailing edge). With no repeat/coda/
        // segno backing it, a bare "left" style must not split it into its
        // own spurious one-measure part; only "right" (a measure that has
        // actually concluded) is trusted for a bare style change.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Chanter</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <note><pitch><step>G</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
              <barline location="left"><bar-style>heavy-light</bar-style></barline>
            </measure>
            <measure number="2">
              <note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
              <note><pitch><step>B</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
            </measure>
          </part>
        </score-partwise>
        """
        let tune = try MusicXMLParser.parse(Data(xml.utf8))
        #expect(tune.parts.count == 1)
        #expect(tune.parts[0].measures.count == 2)
    }

    @Test func rightSideBareStyleChangeStillSplitsParts() throws {
        // The flip side: a bare style change IS trusted on the "right" —
        // a measure that has genuinely just concluded.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Chanter</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <note><pitch><step>G</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
              <barline location="right"><bar-style>light-light</bar-style></barline>
            </measure>
            <measure number="2">
              <note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
            </measure>
          </part>
        </score-partwise>
        """
        let tune = try MusicXMLParser.parse(Data(xml.utf8))
        #expect(tune.parts.count == 2)
        #expect(tune.parts[0].measures.count == 1)
        #expect(tune.parts[1].measures.count == 1)
    }

    @Test func noteTypeOverridesUnreliableDuration() throws {
        // Real file found in the wild: every single note had an identical
        // <duration>16</duration> regardless of its actual <type> (a 16th
        // note and a dotted eighth — a real 6:1 ratio — both reported 16).
        // <type> must win whenever both are present.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Chanter</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <note>
                <pitch><step>A</step><octave>4</octave></pitch>
                <duration>16</duration>
                <type>16th</type>
              </note>
              <note>
                <pitch><step>B</step><octave>4</octave></pitch>
                <duration>16</duration>
                <type>eighth</type>
                <dot/>
              </note>
            </measure>
          </part>
        </score-partwise>
        """
        let tune = try MusicXMLParser.parse(Data(xml.utf8))
        let notes = tune.parts[0].measures[0].notes
        #expect(abs(notes[0].duration - 0.25) < 0.0001)  // 16th, not 16/4=4.0
        #expect(abs(notes[1].duration - 0.75) < 0.0001)  // dotted eighth, not 4.0
    }

    @Test func multiplePartsProduceOneVoiceEach() throws {
        // Real file found in the wild ("Hard Times Come Again No More"): a
        // harmony arrangement with three parts (melody/harm1/harm2), each
        // restarting its own measure numbering at 1, meant to play back
        // *simultaneously* as harmony — not sequential tune sections, and
        // not a lone drone staff to be skipped.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <work><work-title>Harmony Test</work-title></work>
          <part-list>
            <score-part id="P1"><part-name>melody</part-name></score-part>
            <score-part id="P2"><part-name>harm1</part-name></score-part>
            <score-part id="P3"><part-name>harm2</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <direction><sound tempo="100"/></direction>
              <note><pitch><step>G</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
              <note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
            </measure>
          </part>
          <part id="P2">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <note><pitch><step>D</step><octave>5</octave></pitch><duration>4</duration><type>quarter</type></note>
              <note><pitch><step>D</step><octave>5</octave></pitch><duration>4</duration><type>quarter</type></note>
            </measure>
          </part>
          <part id="P3">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <note><pitch><step>B</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
              <note><pitch><step>B</step><octave>4</octave></pitch><duration>4</duration><type>quarter</type></note>
            </measure>
          </part>
        </score-partwise>
        """
        let voices = try MusicXMLParser.parseVoices(Data(xml.utf8))
        #expect(voices.count == 3)
        #expect(voices.map(\.name) == ["melody", "harm1", "harm2"])
        // Every voice shares the score-level title/tempo (one piece, one tempo)...
        #expect(voices.allSatisfy { $0.tune.title == "Harmony Test" })
        #expect(voices.allSatisfy { $0.tune.tempo == 100 })
        // ...but each has its own independent note content.
        #expect(voices[0].tune.parts[0].measures[0].notes.map(\.pitch) == [.lowG, .lowA])
        #expect(voices[1].tune.parts[0].measures[0].notes.map(\.pitch) == [.d, .d])
        #expect(voices[2].tune.parts[0].measures[0].notes.map(\.pitch) == [.b, .b])
    }

    @Test func singlePartFileStillProducesExactlyOneVoiceViaLegacyParse() throws {
        // parse(_:) is the backward-compatible single-voice entry point —
        // still used wherever only "the" tune (not the full voice list)
        // matters.
        let tune = try MusicXMLParser.parse(Data(sample.utf8))
        #expect(tune.title == "Test Tune")
    }

    @Test func metronomeMarkIsUsedWhenNoSoundTempoIsPresent() throws {
        // Real file found in the wild had a <metronome> display mark but
        // zero <sound tempo> elements anywhere — falling back to the flat
        // 90 default made it play noticeably faster than intended.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Chanter</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <direction>
                <direction-type>
                  <metronome><beat-unit>quarter</beat-unit><per-minute>76</per-minute></metronome>
                </direction-type>
              </direction>
              <note>
                <pitch><step>A</step><octave>4</octave></pitch>
                <duration>16</duration>
                <type>quarter</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """
        let tune = try MusicXMLParser.parse(Data(xml.utf8))
        #expect(tune.tempo == 76)
    }
}
