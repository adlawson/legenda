import AVFoundation
import Foundation

public enum SoundCue: String, CaseIterable, Sendable {
    /// Each of the last three seconds of an item.
    case warning = "Tink"
    case itemChange = "Submarine"
    case bufferStart = "Glass"
    case overtime = "Basso"
    case complete = "Hero"

    var fileURL: URL {
        URL(fileURLWithPath: "/System/Library/Sounds/\(rawValue).aiff")
    }

    var volume: Float {
        switch self {
        case .warning: 0.35
        case .itemChange, .bufferStart: 0.5
        case .overtime, .complete: 0.6
        }
    }
}

/// Plays the cues above. Two players per cue because re-triggering a single
/// `AVAudioPlayer` (or `NSSound`) restarts it rather than overlapping, and the
/// warning cue can fire while the previous one is still ringing out.
@MainActor
public final class SoundPlayer {
    public var isMuted = false

    private var players: [SoundCue: [AVAudioPlayer]] = [:]
    private var nextSlot: [SoundCue: Int] = [:]

    public init() {
        for cue in SoundCue.allCases {
            guard FileManager.default.fileExists(atPath: cue.fileURL.path) else { continue }
            let pair = (0..<2).compactMap { _ -> AVAudioPlayer? in
                guard let player = try? AVAudioPlayer(contentsOf: cue.fileURL) else { return nil }
                player.volume = cue.volume
                player.prepareToPlay()
                return player
            }
            if !pair.isEmpty { players[cue] = pair }
        }
    }

    public func play(_ cue: SoundCue) {
        guard !isMuted, let pool = players[cue], !pool.isEmpty else { return }
        let slot = (nextSlot[cue] ?? 0) % pool.count
        nextSlot[cue] = slot + 1
        let player = pool[slot]
        player.currentTime = 0
        player.play()
    }
}
