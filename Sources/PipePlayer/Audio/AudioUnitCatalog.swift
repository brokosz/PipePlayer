import Foundation
import AVFoundation
import AudioToolbox

/// Enumerates installed Audio Unit instruments (`kAudioUnitType_MusicDevice`)
/// so the user can route PipePlayer's playback through another app/plugin
/// registered on the system — MainStage's instruments, Kontakt, or any other
/// third-party instrument AU — instead of only Apple's built-in DLS bank or
/// a bare SoundFont file.
enum AudioUnitCatalog {
    static func availableInstruments() -> [AVAudioUnitComponent] {
        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_MusicDevice
        description.componentSubType = 0
        description.componentManufacturer = 0
        description.componentFlags = 0
        description.componentFlagsMask = 0
        return AVAudioUnitComponentManager.shared()
            .components(matching: description)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
