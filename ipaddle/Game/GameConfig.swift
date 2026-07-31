import Foundation
import CoreGraphics

enum GameMode {
    case classic2D
    case tunnel3D
}

enum GameConfig {
    /// Logical scene size; aspectFit letterboxes on non-4:3 iPads.
    static let sceneSize = CGSize(width: 1024, height: 768)

    static let paddleY: CGFloat = 64
    static let paddleSize = CGSize(width: 150, height: 22)
    static let widePaddleWidth: CGFloat = 230

    static let ballRadius: CGFloat = 9
    static let baseBallSpeed: CGFloat = 470
    static let speedPerLevel: CGFloat = 22
    static let maxBallSpeed: CGFloat = 760
    /// Minimum vertical fraction of velocity, so the ball never gets stuck bouncing horizontally.
    static let minVerticalFraction: CGFloat = 0.18

    static let startLives = 3
    static let maxLives = 6

    static let brickColumns = 13
    static let brickHeight: CGFloat = 30
    static let brickGap: CGFloat = 5
    static let brickTopInset: CGFloat = 100
    static let brickSideInset: CGFloat = 30

    static let powerUpDropChance = 0.22
    static let powerUpFallSpeed: CGFloat = 170
    static let expandDuration: TimeInterval = 12
    static let slowDuration: TimeInterval = 8
    static let slowFactor: CGFloat = 0.65
    static let laserDuration: TimeInterval = 8
    static let laserFireInterval: TimeInterval = 0.45
    static let laserSpeed: CGFloat = 700
}
