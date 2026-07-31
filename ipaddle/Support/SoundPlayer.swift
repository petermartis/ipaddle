import SpriteKit
import UIKit

enum Sound: String, CaseIterable {
    case paddleHit = "paddle_hit.wav"
    case wallHit = "wall_hit.wav"
    case brickHit = "brick_hit.wav"
    case brickBreak = "brick_break.wav"
    case powerUp = "powerup.wav"
    case laser = "laser.wav"
    case loseLife = "lose_life.wav"
    case levelClear = "level_clear.wav"
    case gameOver = "game_over.wav"
}

/// Cached SKActions for low-latency effect playback, plus haptic feedback.
/// (Haptics are a no-op on iPads without a Taptic Engine — harmless.)
enum SoundPlayer {
    private static let actions: [Sound: SKAction] = {
        var dict: [Sound: SKAction] = [:]
        for sound in Sound.allCases {
            dict[sound] = SKAction.playSoundFileNamed(sound.rawValue, waitForCompletion: false)
        }
        return dict
    }()

    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    static func play(_ sound: Sound, on node: SKNode) {
        guard let action = actions[sound] else { return }
        node.run(action)
    }

    static func tapHaptic() { lightImpact.impactOccurred() }
    static func breakHaptic() { mediumImpact.impactOccurred() }
    static func failureHaptic() { notification.notificationOccurred(.error) }
    static func successHaptic() { notification.notificationOccurred(.success) }
}
