import SpriteKit

final class Ball: SKShapeNode {
    static func make() -> Ball {
        let ball = Ball(circleOfRadius: GameConfig.ballRadius)
        ball.name = "ball"
        ball.fillColor = SKColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
        ball.strokeColor = .clear

        let body = SKPhysicsBody(circleOfRadius: GameConfig.ballRadius)
        body.friction = 0
        body.restitution = 1
        body.linearDamping = 0
        body.angularDamping = 0
        body.allowsRotation = false
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = PhysicsCategory.ball
        body.collisionBitMask = PhysicsCategory.wall | PhysicsCategory.brick | PhysicsCategory.paddle
        body.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.brick
            | PhysicsCategory.wall | PhysicsCategory.bottom
        ball.physicsBody = body
        return ball
    }

    /// Sets velocity to `speed` at `angle` (radians, 0 = right, π/2 = up).
    func launch(angle: CGFloat, speed: CGFloat) {
        physicsBody?.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
    }
}
