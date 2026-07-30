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
        // G is written at two distinct octaves across this part (4 and 5) —
        // the octave-rank pre-scan (`MusicXMLParser.octaveRanks(scanning:)`)
        // picks this up and maps the lower one (4) to lowG, the higher one
        // (5) to highG, regardless of melodic context.
        #expect(measure2.map(\.pitch) == [.lowA, .highG, .c])
        #expect(abs(measure2[0].duration - 0.5) < 0.0001)
        #expect(measure2[1].duration < 0.1) // grace note — short, borrowed time
        #expect(abs(measure2[2].duration - 0.5) < 0.0001)
    }

    @Test func melodicContourDisambiguatesRepeatedGAndAOctaves() throws {
        // Two real files from the same source both wrote their intended
        // "high" G/A register at an octave number that collides exactly with
        // this app's lowG/lowA MIDI values (e.g. their high G computed to
        // MIDI 67, identical to lowG) — raw semitone distance can never
        // recover the correct register there, since the numbers are
        // literally the same. This reproduces that pattern directly: a run
        // of upper-register notes (d, e, f) surrounding ambiguous G/A notes
        // should resolve them to the HIGH octave, since jumping down to the
        // low octave and back would be a large, un-piping-like leap.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.1">
          <part-list><score-part id="P1"><part-name>Chanter</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>1</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
              </attributes>
              <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>F</step><octave>4</octave><alter>1</alter></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
            </measure>
          </part>
        </score-partwise>
        """
        let tune = try MusicXMLParser.parse(Data(xml.utf8))
        let notes = tune.parts[0].measures[0].notes
        #expect(notes.map(\.pitch) == [.d, .highG, .f, .highA])
    }

    @Test func octaveRankScanResolvesGAndARegisterEvenAgainstMelodicLeaps() throws {
        // A real OMR exporter (epm_note_extractor.py) writes an entire
        // tune's low G/A register at octave 3 and high register at octave 4
        // — one full octave below what this app's own Pitch enum assumes
        // (lowG/lowA = octave 4, highG/highA = octave 5) — but does so
        // *consistently* throughout the file. Verified against a real tune
        // with an independent, known-correct BWW transcription: this part
        // includes a genuine "E, low A, E" turn figure — a full-octave leap
        // down and back that a melodic-contour ("nearest to previous note")
        // heuristic gets wrong, since a leap to highA would be a smaller,
        // more "plausible" jump. Scanning the whole part first to learn
        // that this file's G/A octaves are {3: low, 4: high} resolves it
        // correctly regardless of the surrounding notes.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.1">
          <part-list><score-part id="P1"><part-name>Chanter</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>1</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
              </attributes>
              <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>A</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>G</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type></note>
            </measure>
          </part>
        </score-partwise>
        """
        let tune = try MusicXMLParser.parse(Data(xml.utf8))
        let notes = tune.parts[0].measures[0].notes
        #expect(notes.map(\.pitch) == [.highG, .e, .lowA, .e, .highA, .lowG])
    }

    @Test func pitchMatchesByPitchClassBeforeFallingBackToRawDistance() {
        // Real file found in the wild (auto-extracted by a third-party
        // tool, "epm_note_extractor.py", likely from audio): several notes
        // were written a full octave or more below the chanter's actual
        // range — A3, D4, F#4, B3 — alongside correctly-written G4/A4. A
        // pure raw-semitone-distance match collapsed ALL of them onto lowG
        // (67) — the chanter's lowest note, and so also numerically closest
        // to anything below the whole range — reported as "the same low
        // note over and over." Matching pitch class first (then using raw
        // distance only to pick octave among same-class candidates, or as a
        // last resort with no pitch-class match at all) fixes this.
        #expect(Pitch.nearest(toMIDINumber: 57) == .lowA)  // A3 -> lowA, not lowG
        #expect(Pitch.nearest(toMIDINumber: 62) == .d)     // D4 -> d, not lowG
        #expect(Pitch.nearest(toMIDINumber: 66) == .f)     // F#4 -> f, not lowG
        #expect(Pitch.nearest(toMIDINumber: 59) == .b)     // B3 -> b, not lowG
        #expect(Pitch.nearest(toMIDINumber: 67) == .lowG)  // G4 -> lowG, correctly
        #expect(Pitch.nearest(toMIDINumber: 69) == .lowA)  // A4 -> lowA, correctly
    }

    @Test func pitchClassMatchStillPicksNearestOctaveForGAndA() {
        // G and A each appear twice in the chanter's scale (low and high
        // octave) — once pitch class narrows it to {lowG, highG} or
        // {lowA, highA}, raw distance should still decide which one. G's
        // pitch class only recurs every 12 semitones, so there's no "middle"
        // value strictly between lowG (67) and highG (79) to test the
        // tiebreak against — using G3 (55, an octave below lowG) and G6 (91,
        // an octave above highG) instead.
        #expect(Pitch.nearest(toMIDINumber: 67) == .lowG)  // G4, exact
        #expect(Pitch.nearest(toMIDINumber: 79) == .highG) // G5, exact
        #expect(Pitch.nearest(toMIDINumber: 55) == .lowG)  // G3: closer to lowG (67) than highG (79)
        #expect(Pitch.nearest(toMIDINumber: 91) == .highG) // G6: closer to highG (79) than lowG (67)
    }

    @Test func tupletScalesDurationByActualOverNormalNotes() throws {
        // A triplet's <type> is still the plain written note value (e.g. an
        // eighth-note triplet is <type>eighth</type> on each note) — without
        // reading <time-modification>, three triplet eighths would play as
        // three full eighths (1.5 beats total instead of the correct 1.0),
        // a real, confirmed gap found by auditing the parser against the
        // MusicXML 4.0 spec rather than only real files.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Chanter</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <note>
                <pitch><step>A</step><octave>4</octave></pitch>
                <duration>2</duration>
                <type>eighth</type>
                <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
              </note>
              <note>
                <pitch><step>B</step><octave>4</octave></pitch>
                <duration>2</duration>
                <type>eighth</type>
                <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
              </note>
              <note>
                <pitch><step>C</step><octave>5</octave><alter>1</alter></pitch>
                <duration>2</duration>
                <type>eighth</type>
                <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
              </note>
              <note>
                <pitch><step>D</step><octave>5</octave></pitch>
                <duration>4</duration>
                <type>quarter</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """
        let tune = try MusicXMLParser.parse(Data(xml.utf8))
        let notes = tune.parts[0].measures[0].notes
        // Each triplet eighth: 0.5 (written eighth) * 2/3 = 0.3333...
        #expect(abs(notes[0].duration - (0.5 * 2.0 / 3.0)) < 0.0001)
        #expect(abs(notes[1].duration - (0.5 * 2.0 / 3.0)) < 0.0001)
        #expect(abs(notes[2].duration - (0.5 * 2.0 / 3.0)) < 0.0001)
        // Non-tuplet quarter note right after: unaffected, still a full 1.0.
        #expect(abs(notes[3].duration - 1.0) < 0.0001)
        // The three triplet notes plus the quarter should sum to exactly
        // 2.0 beats (one eighth-triplet "group" = 1 written beat, matching
        // the two eighths' worth of time it's squeezed into).
        let totalTripletDuration = notes[0].duration + notes[1].duration + notes[2].duration
        #expect(abs(totalTripletDuration - 1.0) < 0.0001)
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
