import SpriteKit

/// A destructible (or indestructible) brick. Built from a level-map character.
final class Brick: SKSpriteNode {
    private(set) var hitPoints: Int
    let isIndestructible: Bool
    let pointValue: Int

    private static func style(for char: Character) -> (hp: Int, points: Int, color: SKColor, indestructible: Bool)? {
        switch char {
        case "1": return (1, 50, SKColor(red: 0.37, green: 0.75, blue: 0.35, alpha: 1), false)
        case "2": return (2, 100, SKColor(red: 0.28, green: 0.55, blue: 0.92, alpha: 1), false)
        case "3": return (3, 150, SKColor(red: 0.89, green: 0.24, blue: 0.24, alpha: 1), false)
        case "X": return (0, 0, SKColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1), true)
        default: return nil
        }
    }

    static func make(from char: Character, size: CGSize) -> Brick? {
        guard let s = style(for: char) else { return nil }
        return Brick(size: size, hp: s.hp, points: s.points, color: s.color, indestructible: s.indestructible)
    }

    private init(size: CGSize, hp: Int, points: Int, color: SKColor, indestructible: Bool) {
        hitPoints = hp
        pointValue = points
        isIndestructible = indestructible
        super.init(texture: nil, color: color, size: size)

        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.friction = 0
        body.restitution = 1
        body.categoryBitMask = PhysicsCategory.brick
        body.contactTestBitMask = PhysicsCategory.ball | PhysicsCategory.laser
        physicsBody = body

        // top highlight strip for a bit of depth
        let highlight = SKSpriteNode(color: SKColor.white.withAlphaComponent(0.28),
                                     size: CGSize(width: size.width, height: size.height * 0.22))
        highlight.position = CGPoint(x: 0, y: size.height * 0.39)
        highlight.zPosition = 1
        addChild(highlight)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Applies one hit. Returns true if the brick was destroyed.
    func takeHit() -> Bool {
        guard !isIndestructible else { return false }
        hitPoints -= 1
        if hitPoints <= 0 { return true }
        alpha = 0.45 + 0.55 * CGFloat(hitPoints) / 3.0
        run(SKAction.sequence([
            SKAction.scale(to: 0.92, duration: 0.05),
            SKAction.scale(to: 1.0, duration: 0.05),
        ]))
        return false
    }
}
