import SpriteKit

final class GameOverScene: SKScene {
    private let score: Int
    private let didWin: Bool
    private let mode: GameMode
    private let isNewHighScore: Bool

    init(score: Int, didWin: Bool, mode: GameMode) {
        self.score = score
        self.didWin = didWin
        self.mode = mode
        self.isNewHighScore = HighScoreStore.submit(score)
        super.init(size: GameConfig.sceneSize)
        scaleMode = .aspectFit
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1)
        SoundPlayer.play(didWin ? .levelClear : .gameOver, on: self)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = didWin ? "YOU WIN!" : "GAME OVER"
        title.fontSize = 80
        title.fontColor = didWin
            ? SKColor(red: 0.37, green: 0.75, blue: 0.35, alpha: 1)
            : SKColor(red: 0.89, green: 0.24, blue: 0.24, alpha: 1)
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        addChild(title)

        let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        scoreLabel.text = "SCORE  \(score)"
        scoreLabel.fontSize = 36
        scoreLabel.fontColor = .white
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.48)
        addChild(scoreLabel)

        let high = SKLabelNode(fontNamed: "AvenirNext-Bold")
        high.text = isNewHighScore
            ? "★ NEW HIGH SCORE ★"
            : "HIGH SCORE  \(HighScoreStore.highScore)"
        high.fontSize = 26
        high.fontColor = SKColor(red: 0.94, green: 0.62, blue: 0.20, alpha: 1)
        high.position = CGPoint(x: size.width / 2, y: size.height * 0.40)
        addChild(high)
        if isNewHighScore {
            high.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.12, duration: 0.4),
                SKAction.scale(to: 1.0, duration: 0.4),
            ])))
        }

        let again = SKLabelNode(fontNamed: "AvenirNext-Bold")
        again.name = "againButton"
        again.text = "PLAY AGAIN"
        again.fontSize = 32
        again.fontColor = .white
        again.position = CGPoint(x: size.width / 2, y: size.height * 0.26)
        again.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.4, duration: 0.7),
            SKAction.fadeAlpha(to: 1.0, duration: 0.7),
        ])))
        addChild(again)

        let menu = SKLabelNode(fontNamed: "AvenirNext-Bold")
        menu.name = "menuButton"
        menu.text = "MENU"
        menu.fontSize = 24
        menu.fontColor = SKColor.white.withAlphaComponent(0.6)
        menu.position = CGPoint(x: size.width / 2, y: size.height * 0.16)
        addChild(menu)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self) else { return }
        if nodes(at: location).contains(where: { $0.name == "menuButton" }) {
            view?.presentScene(MenuScene.make(), transition: .fade(withDuration: 0.4))
        } else {
            let game: SKScene
            switch mode {
            case .classic2D:
                game = GameScene(levelIndex: 0, score: 0, lives: GameConfig.startLives)
            case .tunnel3D:
                game = GameScene3D(levelIndex: 0, score: 0, lives: GameConfig.startLives)
            }
            view?.presentScene(game, transition: .doorway(withDuration: 0.6))
        }
    }
}
