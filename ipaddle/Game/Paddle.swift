import SpriteKit

final class Paddle: SKSpriteNode {
    private(set) var isWide = false
    private(set) var hasLaser = false
    private var cannons: [SKSpriteNode] = []

    init() {
        super.init(texture: nil,
                   color: SKColor(red: 0.82, green: 0.84, blue: 0.90, alpha: 1),
                   size: GameConfig.paddleSize)
        name = "paddle"

        let highlight = SKSpriteNode(color: SKColor.white.withAlphaComponent(0.35),
                                     size: CGSize(width: size.width, height: 6))
        highlight.name = "highlight"
        highlight.position = CGPoint(x: 0, y: size.height / 2 - 4)
        highlight.zPosition = 1
        addChild(highlight)

        rebuildBody()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func rebuildBody() {
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.friction = 0
        body.restitution = 1
        body.categoryBitMask = PhysicsCategory.paddle
        body.contactTestBitMask = PhysicsCategory.ball | PhysicsCategory.powerUp
        physicsBody = body
    }

    private func setWidth(_ width: CGFloat) {
        size = CGSize(width: width, height: size.height)
        (childNode(withName: "highlight") as? SKSpriteNode)?
            .size = CGSize(width: width, height: 6)
        rebuildBody()
        layoutCannons()
    }

    func setWide(_ wide: Bool) {
        guard wide != isWide else { return }
        isWide = wide
        setWidth(wide ? GameConfig.widePaddleWidth : GameConfig.paddleSize.width)
    }

    func setLaser(_ on: Bool) {
        guard on != hasLaser else { return }
        hasLaser = on
        layoutCannons()
    }

    private func layoutCannons() {
        cannons.forEach { $0.removeFromParent() }
        cannons = []
        guard hasLaser else { return }
        for dx: CGFloat in [-1, 1] {
            let cannon = SKSpriteNode(color: SKColor(red: 0.89, green: 0.24, blue: 0.24, alpha: 1),
                                      size: CGSize(width: 12, height: 14))
            cannon.position = CGPoint(x: dx * (size.width / 2 - 10), y: size.height / 2 + 4)
            cannon.zPosition = 1
            addChild(cannon)
            cannons.append(cannon)
        }
    }

    /// World-space x positions of the two laser muzzles.
    var muzzleOffsets: [CGFloat] {
        [-(size.width / 2 - 10), size.width / 2 - 10]
    }
}
