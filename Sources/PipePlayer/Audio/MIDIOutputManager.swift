import Foundation
import CoreMIDI

/// Owns a virtual CoreMIDI source named "PipePlayer" so other apps (Logic,
/// MainStage, GarageBand, or anything listening for MIDI input, including
/// hardware synths routed through an IAC bus) can select it as an input and
/// receive the tune being played — independent of whether local audio
/// playback is also enabled.
final class MIDIOutputManager {

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private(set) var isAvailable = false

    init() {
        let status = MIDIClientCreateWithBlock("PipePlayer" as CFString, &client) { _ in }
        guard status == noErr else {
            print("PipePlayer: failed to create MIDI client (status \(status))")
            return
        }
        let sourceStatus = MIDISourceCreate(client, "PipePlayer" as CFString, &source)
        guard sourceStatus == noErr else {
            print("PipePlayer: failed to create virtual MIDI source (status \(sourceStatus))")
            return
        }
        isAvailable = true
    }

    deinit {
        if source != 0 { MIDIEndpointDispose(source) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        send([0x90 | (channel & 0x0F), note, velocity])
    }

    func sendNoteOff(note: UInt8, channel: UInt8 = 0) {
        send([0x80 | (channel & 0x0F), note, 0])
    }

    func sendAllNotesOff(channel: UInt8 = 0) {
        for note: UInt8 in 0...127 {
            send([0x80 | (channel & 0x0F), note, 0])
        }
    }

    private func send(_ bytes: [UInt8]) {
        guard isAvailable else { return }
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        var mutableBytes = bytes
        _ = MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0, mutableBytes.count, &mutableBytes)
        MIDIReceived(source, &packetList)
    }
}
