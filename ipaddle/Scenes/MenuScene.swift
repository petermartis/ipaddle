import SpriteKit

final class MenuScene: SKScene {
    static func make() -> MenuScene {
        let scene = MenuScene(size: GameConfig.sceneSize)
        scene.scaleMode = .aspectFit
        return scene
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1)

        // decorative brick rows behind the title
        let colors: [SKColor] = [
            SKColor(red: 0.89, green: 0.24, blue: 0.24, alpha: 1),
            SKColor(red: 0.94, green: 0.62, blue: 0.20, alpha: 1),
            SKColor(red: 0.37, green: 0.75, blue: 0.35, alpha: 1),
            SKColor(red: 0.28, green: 0.55, blue: 0.92, alpha: 1),
        ]
        for (row, color) in colors.enumerated() {
            for col in 0..<9 {
                let brick = SKSpriteNode(color: color.withAlphaComponent(0.22),
                                         size: CGSize(width: 92, height: 26))
                brick.position = CGPoint(x: 130 + CGFloat(col) * 98,
                                         y: size.height - 120 - CGFloat(row) * 34)
                addChild(brick)
            }
        }

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "iPADDLE"
        title.fontSize = 92
        title.fontColor = .white
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.58)
        addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-Bold")
        subtitle.text = "\(Levels.all.count) LEVELS · POWER-UPS · LASERS"
        subtitle.fontSize = 22
        subtitle.fontColor = SKColor.white.withAlphaComponent(0.55)
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.48)
        addChild(subtitle)

        let high = SKLabelNode(fontNamed: "AvenirNext-Bold")
        high.text = "HIGH SCORE  \(HighScoreStore.highScore)"
        high.fontSize = 26
        high.fontColor = SKColor(red: 0.94, green: 0.62, blue: 0.20, alpha: 1)
        high.position = CGPoint(x: size.width / 2, y: size.height * 0.38)
        addChild(high)

        addModeButton(text: "PLAY 2D", name: "play2d",
                      center: CGPoint(x: size.width / 2 - 150, y: size.height * 0.24))
        addModeButton(text: "PLAY 3D", name: "play3d",
                      center: CGPoint(x: size.width / 2 + 150, y: size.height * 0.24))
    }

    private func addModeButton(text: String, name: String, center: CGPoint) {
        let button = SKShapeNode(rectOf: CGSize(width: 240, height: 72), cornerRadius: 14)
        button.name = name
        button.position = center
        button.fillColor = SKColor.white.withAlphaComponent(0.08)
        button.strokeColor = SKColor.white.withAlphaComponent(0.8)
        button.lineWidth = 2
        addChild(button)

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.name = name
        label.text = text
        label.fontSize = 30
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        button.addChild(label)

        button.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.7),
            SKAction.fadeAlpha(to: 1.0, duration: 0.7),
        ])))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self) else { return }
        let tapped = nodes(at: location).compactMap(\.name)
        if tapped.contains("play3d") {
            let game = GameScene3D(levelIndex: 0, score: 0, lives: GameConfig.startLives)
            view?.presentScene(game, transition: .doorway(withDuration: 0.6))
        } else if tapped.contains("play2d") {
            let game = GameScene(levelIndex: 0, score: 0, lives: GameConfig.startLives)
            view?.presentScene(game, transition: .doorway(withDuration: 0.6))
        }
    }
}
