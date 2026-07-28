import Foundation
import Testing

@testable import LegendaCore

@MainActor
@Suite("Sound cues")
struct SoundCueTests {

    /// The cues point at stock macOS sounds by path. If an OS update ever moves
    /// or renames one, this should fail here rather than going silent in a meeting.
    @Test("Every cue resolves to a file that exists", arguments: SoundCue.allCases)
    func cueFileExists(cue: SoundCue) {
        #expect(FileManager.default.fileExists(atPath: cue.fileURL.path), "missing \(cue.rawValue)")
    }

    @Test("Muting silences playback without tearing down the players")
    func mutingIsRespected() {
        let player = SoundPlayer()
        player.isMuted = true
        // Should be a no-op rather than a crash.
        for cue in SoundCue.allCases { player.play(cue) }
    }
}
