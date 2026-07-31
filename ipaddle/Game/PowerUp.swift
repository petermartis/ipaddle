import SpriteKit

enum PowerUpKind: CaseIterable {
    case expand
    case multiball
    case slow
    case laser
    case extraLife

    var letter: String {
        switch self {
        case .expand: return "E"
        case .multiball: return "M"
        case .slow: return "S"
        case .laser: return "L"
        case .extraLife: return "+"
        }
    }

    var color: SKColor {
        switch self {
        case .expand: return SKColor(red: 0.28, green: 0.55, blue: 0.92, alpha: 1)
        case .multiball: return SKColor(red: 0.61, green: 0.35, blue: 0.89, alpha: 1)
        case .slow: return SKColor(red: 0.94, green: 0.62, blue: 0.20, alpha: 1)
        case .laser: return SKColor(red: 0.89, green: 0.24, blue: 0.24, alpha: 1)
        case .extraLife: return SKColor(red: 0.37, green: 0.75, blue: 0.35, alpha: 1)
        }
    }
}

/// A capsule that falls from a destroyed brick; caught with the paddle.
final class PowerUpNode: SKNode {
    let kind: PowerUpKind

    init(kind: PowerUpKind) {
        self.kind = kind
        super.init()

        let size = CGSize(width: 52, height: 26)
        let capsule = SKShapeNode(rectOf: size, cornerRadius: 13)
        capsule.fillColor = kind.color
        capsule.strokeColor = SKColor.white.withAlphaComponent(0.7)
        capsule.lineWidth = 2
        addChild(capsule)

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = kind.letter
        label.fontSize = 19
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        addChild(label)

        let body = SKPhysicsBody(rectangleOf: size)
        body.affectedByGravity = false
        body.linearDamping = 0
        body.categoryBitMask = PhysicsCategory.powerUp
        body.collisionBitMask = PhysicsCategory.none
        body.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.bottom
        body.velocity = CGVector(dx: 0, dy: -GameConfig.powerUpFallSpeed)
        physicsBody = body

        run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.35),
            SKAction.fadeAlpha(to: 1.0, duration: 0.35),
        ])))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
