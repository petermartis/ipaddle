import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate {
    // MARK: - State

    private let levelIndex: Int
    private var score: Int
    private var lives: Int

    private var ballOnPaddle = true
    private var slowActive = false
    private var isGamePaused = false
    private var isTransitioning = false

    /// Everything pausable (paddle, balls, bricks, capsules) lives under this node.
    private let gameNode = SKNode()
    private let paddle = Paddle()
    private var servingBall: Ball?

    private var scoreLabel: SKLabelNode?
    private var livesLabel: SKLabelNode?
    private var hintLabel: SKLabelNode?
    private var pauseOverlay: SKNode?
    private var controlTouch: UITouch?
    private var touchMovedDistance: CGFloat = 0

    // MARK: - Init

    init(levelIndex: Int, score: Int, lives: Int) {
        self.levelIndex = levelIndex
        self.score = score
        self.lives = lives
        super.init(size: GameConfig.sceneSize)
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var targetBallSpeed: CGFloat {
        let speed = min(GameConfig.baseBallSpeed + CGFloat(levelIndex) * GameConfig.speedPerLevel,
                        GameConfig.maxBallSpeed)
        return slowActive ? speed * GameConfig.slowFactor : speed
    }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        addChild(gameNode)

        setupWalls()
        setupHUD()
        buildBricks()

        paddle.position = CGPoint(x: size.width / 2, y: GameConfig.paddleY)
        gameNode.addChild(paddle)

        spawnServingBall()
    }

    private func setupWalls() {
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: 0, y: -60))
        wallPath.addLine(to: CGPoint(x: 0, y: size.height))
        wallPath.addLine(to: CGPoint(x: size.width, y: size.height))
        wallPath.addLine(to: CGPoint(x: size.width, y: -60))
        let walls = SKNode()
        let wallBody = SKPhysicsBody(edgeChainFrom: wallPath)
        wallBody.friction = 0
        wallBody.restitution = 1
        wallBody.categoryBitMask = PhysicsCategory.wall
        walls.physicsBody = wallBody
        addChild(walls)

        let bottom = SKNode()
        let bottomBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 40))
        bottomBody.isDynamic = false
        bottomBody.categoryBitMask = PhysicsCategory.bottom
        bottomBody.collisionBitMask = PhysicsCategory.none
        bottomBody.contactTestBitMask = PhysicsCategory.ball | PhysicsCategory.powerUp
        bottom.position = CGPoint(x: size.width / 2, y: -40)
        bottom.physicsBody = bottomBody
        addChild(bottom)
    }

    private func setupHUD() {
        let hudY = size.height - 44

        let score = SKLabelNode(fontNamed: "AvenirNext-Bold")
        score.fontSize = 24
        score.fontColor = .white
        score.horizontalAlignmentMode = .left
        score.position = CGPoint(x: 24, y: hudY)
        score.zPosition = 10
        addChild(score)
        scoreLabel = score

        let level = SKLabelNode(fontNamed: "AvenirNext-Bold")
        level.fontSize = 24
        level.fontColor = SKColor.white.withAlphaComponent(0.6)
        level.text = "LEVEL \(levelIndex + 1)"
        level.position = CGPoint(x: size.width / 2, y: hudY)
        level.zPosition = 10
        addChild(level)

        let livesNode = SKLabelNode(fontNamed: "AvenirNext-Bold")
        livesNode.fontSize = 24
        livesNode.fontColor = SKColor(red: 0.89, green: 0.24, blue: 0.24, alpha: 1)
        livesNode.horizontalAlignmentMode = .right
        livesNode.position = CGPoint(x: size.width - 80, y: hudY)
        livesNode.zPosition = 10
        addChild(livesNode)
        livesLabel = livesNode

        let pause = SKLabelNode(fontNamed: "AvenirNext-Bold")
        pause.name = "pauseButton"
        pause.text = "❚❚"
        pause.fontSize = 24
        pause.fontColor = SKColor.white.withAlphaComponent(0.7)
        pause.horizontalAlignmentMode = .right
        pause.position = CGPoint(x: size.width - 24, y: hudY)
        pause.zPosition = 10
        addChild(pause)

        refreshHUD()
    }

    private func refreshHUD() {
        scoreLabel?.text = "SCORE \(score)"
        livesLabel?.text = String(repeating: "♥", count: max(0, lives))
    }

    private func buildBricks() {
        let rows = Levels.all[levelIndex]
        let columns = GameConfig.brickColumns
        let usableWidth = size.width - 2 * GameConfig.brickSideInset
        let brickWidth = (usableWidth - CGFloat(columns - 1) * GameConfig.brickGap) / CGFloat(columns)
        let brickSize = CGSize(width: brickWidth, height: GameConfig.brickHeight)

        for (rowIndex, row) in rows.enumerated() {
            for (colIndex, char) in row.enumerated() where colIndex < columns {
                guard let brick = Brick.make(from: char, size: brickSize) else { continue }
                let x = GameConfig.brickSideInset + brickWidth / 2
                    + CGFloat(colIndex) * (brickWidth + GameConfig.brickGap)
                let y = size.height - GameConfig.brickTopInset - GameConfig.brickHeight / 2
                    - CGFloat(rowIndex) * (GameConfig.brickHeight + GameConfig.brickGap)
                brick.position = CGPoint(x: x, y: y)
                gameNode.addChild(brick)
            }
        }
    }

    // MARK: - Serving

    private func spawnServingBall() {
        let ball = Ball.make()
        ball.physicsBody?.isDynamic = false
        ball.position = servePosition()
        gameNode.addChild(ball)
        servingBall = ball
        ballOnPaddle = true

        let hint = SKLabelNode(fontNamed: "AvenirNext-Bold")
        hint.text = "TAP TO LAUNCH"
        hint.fontSize = 22
        hint.fontColor = SKColor.white.withAlphaComponent(0.8)
        hint.position = CGPoint(x: size.width / 2, y: size.height * 0.35)
        hint.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.25, duration: 0.6),
            SKAction.fadeAlpha(to: 0.8, duration: 0.6),
        ])))
        addChild(hint)
        hintLabel = hint
    }

    private func servePosition() -> CGPoint {
        CGPoint(x: paddle.position.x,
                y: paddle.position.y + paddle.size.height / 2 + GameConfig.ballRadius + 2)
    }

    private func launchBall() {
        guard let ball = servingBall else { return }
        ball.physicsBody?.isDynamic = true
        // slight random tilt so serves aren't perfectly vertical
        let angle = CGFloat.pi / 2 + CGFloat.random(in: -0.35...0.35)
        ball.launch(angle: angle, speed: targetBallSpeed)
        servingBall = nil
        ballOnPaddle = false
        hintLabel?.removeFromParent()
        hintLabel = nil
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if isGamePaused {
            handlePauseOverlayTap(at: location)
            return
        }
        if nodes(at: location).contains(where: { $0.name == "pauseButton" }) {
            setPaused(true)
            return
        }
        if controlTouch == nil {
            controlTouch = touch
            touchMovedDistance = 0
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = controlTouch, touches.contains(touch), !isGamePaused else { return }
        let location = touch.location(in: self)
        let previous = touch.previousLocation(in: self)
        touchMovedDistance += abs(location.x - previous.x) + abs(location.y - previous.y)
        movePaddle(toX: location.x)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = controlTouch, touches.contains(touch) else { return }
        controlTouch = nil
        if !isGamePaused, ballOnPaddle, touchMovedDistance < 12 {
            launchBall()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = controlTouch, touches.contains(touch) { controlTouch = nil }
    }

    private func movePaddle(toX x: CGFloat) {
        let half = paddle.size.width / 2
        paddle.position.x = min(max(x, half + 6), size.width - half - 6)
        if ballOnPaddle { servingBall?.position = servePosition() }
    }

    // MARK: - Pause

    private func setPaused(_ paused: Bool) {
        isGamePaused = paused
        gameNode.isPaused = paused
        physicsWorld.speed = paused ? 0 : 1

        if paused {
            let overlay = SKNode()
            overlay.zPosition = 100

            let dim = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.6), size: size)
            dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
            overlay.addChild(dim)

            let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
            title.text = "PAUSED"
            title.fontSize = 52
            title.fontColor = .white
            title.position = CGPoint(x: size.width / 2, y: size.height * 0.6)
            overlay.addChild(title)

            let resume = SKLabelNode(fontNamed: "AvenirNext-Bold")
            resume.name = "resumeButton"
            resume.text = "RESUME"
            resume.fontSize = 32
            resume.fontColor = SKColor(red: 0.37, green: 0.75, blue: 0.35, alpha: 1)
            resume.position = CGPoint(x: size.width / 2, y: size.height * 0.44)
            overlay.addChild(resume)

            let quit = SKLabelNode(fontNamed: "AvenirNext-Bold")
            quit.name = "quitButton"
            quit.text = "QUIT TO MENU"
            quit.fontSize = 24
            quit.fontColor = SKColor.white.withAlphaComponent(0.7)
            quit.position = CGPoint(x: size.width / 2, y: size.height * 0.34)
            overlay.addChild(quit)

            addChild(overlay)
            pauseOverlay = overlay
        } else {
            pauseOverlay?.removeFromParent()
            pauseOverlay = nil
        }
    }

    private func handlePauseOverlayTap(at location: CGPoint) {
        let tapped = nodes(at: location).compactMap(\.name)
        if tapped.contains("resumeButton") {
            setPaused(false)
        } else if tapped.contains("quitButton") {
            HighScoreStore.submit(score)
            view?.presentScene(MenuScene.make(), transition: .fade(withDuration: 0.4))
        }
    }

    // MARK: - Frame update

    override func update(_ currentTime: TimeInterval) {
        guard !isGamePaused, !isTransitioning else { return }

        for case let ball as Ball in gameNode.children where ball !== servingBall {
            guard let body = ball.physicsBody, body.isDynamic else { continue }
            var v = body.velocity
            let speed = hypot(v.dx, v.dy)
            if speed < 1 {
                ball.launch(angle: .pi / 2, speed: targetBallSpeed)
                continue
            }
            // keep speed constant and never let the ball travel near-horizontally
            var scale = targetBallSpeed / speed
            v = CGVector(dx: v.dx * scale, dy: v.dy * scale)
            let minVy = GameConfig.minVerticalFraction * targetBallSpeed
            if abs(v.dy) < minVy {
                let sign: CGFloat = v.dy >= 0 ? 1 : -1
                let vx = sqrt(max(0, targetBallSpeed * targetBallSpeed - minVy * minVy))
                v = CGVector(dx: v.dx >= 0 ? vx : -vx, dy: sign * minVy)
            }
            body.velocity = v
        }

        // cull lasers that flew off the top
        for node in gameNode.children where node.name == "laser" && node.position.y > size.height + 40 {
            node.removeFromParent()
        }
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        guard !isTransitioning else { return }
        let (first, second) = contact.bodyA.categoryBitMask <= contact.bodyB.categoryBitMask
            ? (contact.bodyA, contact.bodyB)
            : (contact.bodyB, contact.bodyA)

        switch (first.categoryBitMask, second.categoryBitMask) {
        case (PhysicsCategory.ball, PhysicsCategory.paddle):
            if let ball = first.node as? Ball { bounceOffPaddle(ball) }

        case (PhysicsCategory.ball, PhysicsCategory.brick):
            if let brick = second.node as? Brick { hit(brick) }

        case (PhysicsCategory.ball, PhysicsCategory.wall):
            SoundPlayer.play(.wallHit, on: self)

        case (PhysicsCategory.ball, PhysicsCategory.bottom):
            if let ball = first.node as? Ball { ballLost(ball) }

        case (PhysicsCategory.paddle, PhysicsCategory.powerUp):
            if let capsule = second.node as? PowerUpNode { catchPowerUp(capsule) }

        case (PhysicsCategory.bottom, PhysicsCategory.powerUp):
            second.node?.removeFromParent()

        case (PhysicsCategory.brick, PhysicsCategory.laser):
            second.node?.removeFromParent()
            if let brick = first.node as? Brick { hit(brick) }

        default:
            break
        }
    }

    private func bounceOffPaddle(_ ball: Ball) {
        // Reflect angle depends on where the ball strikes the paddle: edges send it wide.
        let offset = (ball.position.x - paddle.position.x) / (paddle.size.width / 2)
        let clamped = min(max(offset, -1), 1)
        let angle = CGFloat.pi / 2 - clamped * (CGFloat.pi / 3) // up ± 60°
        ball.launch(angle: angle, speed: targetBallSpeed)
        SoundPlayer.play(.paddleHit, on: self)
        SoundPlayer.tapHaptic()
    }

    private func hit(_ brick: Brick) {
        guard brick.parent != nil else { return }
        if brick.takeHit() {
            score += brick.pointValue
            refreshHUD()
            spawnFragments(at: brick.position, color: brick.color)
            maybeDropPowerUp(at: brick.position)
            brick.removeFromParent()
            SoundPlayer.play(.brickBreak, on: self)
            SoundPlayer.breakHaptic()
            checkLevelCleared()
        } else if brick.isIndestructible {
            SoundPlayer.play(.wallHit, on: self)
        } else {
            SoundPlayer.play(.brickHit, on: self)
        }
    }

    private func spawnFragments(at position: CGPoint, color: SKColor) {
        for _ in 0..<6 {
            let fragment = SKSpriteNode(color: color, size: CGSize(width: 7, height: 7))
            fragment.position = position
            fragment.zPosition = 5
            gameNode.addChild(fragment)
            let dx = CGFloat.random(in: -70...70)
            let dy = CGFloat.random(in: 20...110)
            fragment.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 0.35),
                    SKAction.fadeOut(withDuration: 0.35),
                    SKAction.scale(to: 0.3, duration: 0.35),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    // MARK: - Power-ups

    private func maybeDropPowerUp(at position: CGPoint) {
        guard Double.random(in: 0...1) < GameConfig.powerUpDropChance else { return }
        let kind = PowerUpKind.allCases.randomElement()!
        let capsule = PowerUpNode(kind: kind)
        capsule.position = position
        gameNode.addChild(capsule)
    }

    private func catchPowerUp(_ capsule: PowerUpNode) {
        guard capsule.parent != nil else { return }
        let kind = capsule.kind
        capsule.removeFromParent()
        SoundPlayer.play(.powerUp, on: self)
        SoundPlayer.successHaptic()

        switch kind {
        case .expand:
            paddle.setWide(true)
            gameNode.removeAction(forKey: "expandTimer")
            gameNode.run(SKAction.sequence([
                SKAction.wait(forDuration: GameConfig.expandDuration),
                SKAction.run { [weak self] in self?.paddle.setWide(false) },
            ]), withKey: "expandTimer")

        case .slow:
            slowActive = true
            gameNode.removeAction(forKey: "slowTimer")
            gameNode.run(SKAction.sequence([
                SKAction.wait(forDuration: GameConfig.slowDuration),
                SKAction.run { [weak self] in self?.slowActive = false },
            ]), withKey: "slowTimer")

        case .laser:
            paddle.setLaser(true)
            gameNode.removeAction(forKey: "laserFire")
            gameNode.removeAction(forKey: "laserTimer")
            gameNode.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: GameConfig.laserFireInterval),
                SKAction.run { [weak self] in self?.fireLasers() },
            ])), withKey: "laserFire")
            gameNode.run(SKAction.sequence([
                SKAction.wait(forDuration: GameConfig.laserDuration),
                SKAction.run { [weak self] in
                    self?.paddle.setLaser(false)
                    self?.gameNode.removeAction(forKey: "laserFire")
                },
            ]), withKey: "laserTimer")

        case .extraLife:
            lives = min(lives + 1, GameConfig.maxLives)
            refreshHUD()

        case .multiball:
            spawnMultiballs()
        }
    }

    private func fireLasers() {
        guard paddle.hasLaser else { return }
        for offset in paddle.muzzleOffsets {
            let bolt = SKSpriteNode(color: SKColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1),
                                    size: CGSize(width: 4, height: 20))
            bolt.name = "laser"
            bolt.position = CGPoint(x: paddle.position.x + offset,
                                    y: paddle.position.y + paddle.size.height / 2 + 12)
            let body = SKPhysicsBody(rectangleOf: bolt.size)
            body.affectedByGravity = false
            body.linearDamping = 0
            body.categoryBitMask = PhysicsCategory.laser
            body.collisionBitMask = PhysicsCategory.none
            body.contactTestBitMask = PhysicsCategory.brick
            body.velocity = CGVector(dx: 0, dy: GameConfig.laserSpeed)
            bolt.physicsBody = body
            gameNode.addChild(bolt)
        }
        SoundPlayer.play(.laser, on: self)
    }

    private func spawnMultiballs() {
        let origin: CGPoint
        if let serving = servingBall {
            origin = serving.position
        } else if let live = gameNode.children.first(where: { $0 is Ball && $0 !== servingBall }) {
            origin = live.position
        } else {
            origin = servePosition()
        }
        for angle in [CGFloat.pi / 3, 2 * CGFloat.pi / 3] {
            let ball = Ball.make()
            ball.position = origin
            gameNode.addChild(ball)
            ball.launch(angle: angle, speed: targetBallSpeed)
        }
    }

    // MARK: - Losing / winning

    private func ballLost(_ ball: Ball) {
        guard ball.parent != nil else { return }
        ball.removeFromParent()
        let ballsLeft = gameNode.children.contains { $0 is Ball }
        guard !ballsLeft else { return }

        lives -= 1
        refreshHUD()
        SoundPlayer.play(.loseLife, on: self)
        SoundPlayer.failureHaptic()
        resetPowerUps()

        if lives <= 0 {
            gameOver(didWin: false)
        } else {
            spawnServingBall()
        }
    }

    private func resetPowerUps() {
        paddle.setWide(false)
        paddle.setLaser(false)
        slowActive = false
        for key in ["expandTimer", "slowTimer", "laserFire", "laserTimer"] {
            gameNode.removeAction(forKey: key)
        }
        for node in gameNode.children where node is PowerUpNode || node.name == "laser" {
            node.removeFromParent()
        }
    }

    private func checkLevelCleared() {
        let remaining = gameNode.children.contains {
            ($0 as? Brick).map { !$0.isIndestructible } ?? false
        }
        guard !remaining else { return }
        isTransitioning = true
        resetPowerUps()
        for node in gameNode.children where node is Ball { node.removeFromParent() }
        SoundPlayer.play(.levelClear, on: self)
        SoundPlayer.successHaptic()

        let banner = SKLabelNode(fontNamed: "AvenirNext-Bold")
        banner.text = "LEVEL \(levelIndex + 1) CLEARED!"
        banner.fontSize = 44
        banner.fontColor = .white
        banner.setScale(0.1)
        banner.position = CGPoint(x: size.width / 2, y: size.height / 2)
        banner.zPosition = 50
        addChild(banner)
        banner.run(SKAction.scale(to: 1.0, duration: 0.3))

        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.4),
            SKAction.run { [weak self] in self?.advance() },
        ]))
    }

    private func advance() {
        if levelIndex + 1 >= Levels.all.count {
            gameOver(didWin: true)
        } else {
            let next = GameScene(levelIndex: levelIndex + 1, score: score, lives: lives)
            view?.presentScene(next, transition: .doorway(withDuration: 0.6))
        }
    }

    private func gameOver(didWin: Bool) {
        isTransitioning = true
        let scene = GameOverScene(score: score, didWin: didWin, mode: .classic2D)
        view?.presentScene(scene, transition: .fade(withDuration: 0.6))
    }
}
