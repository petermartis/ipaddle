import SpriteKit

/// Blockout-style tunnel mode: the playfield is a 3D box seen head-on, the
/// paddle is a translucent pane at the front plane moving in X/Y, and the
/// ball flies into the depth, bouncing off all four walls and the rear wall.
/// Rendering is manual perspective projection onto the SpriteKit plane.
final class GameScene3D: SKScene {
    // MARK: - State

    private let levelIndex: Int
    private var score: Int
    private var lives: Int

    private var ballPos = Vec3.zero
    private var ballVel = Vec3.zero
    private var ballInPlay = false
    private var paddleXY = CGPoint.zero // world x/y of the paddle center at z = 0

    private var bricks: [Brick3D] = []
    private let gameNode = SKNode()

    private var ballNode: SKShapeNode?
    private var paddleNode: SKShapeNode?
    private var depthRing: SKShapeNode?
    private var scoreLabel: SKLabelNode?
    private var livesLabel: SKLabelNode?
    private var hintLabel: SKLabelNode?
    private var pauseOverlay: SKNode?

    private var controlTouch: UITouch?
    private var touchMovedDistance: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0
    private var isGamePaused = false
    private var isTransitioning = false

    // MARK: - Init

    init(levelIndex: Int, score: Int, lives: Int) {
        self.levelIndex = levelIndex
        self.score = score
        self.lives = lives
        super.init(size: GameConfig.sceneSize)
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.03, green: 0.045, blue: 0.09, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var targetBallSpeed: CGFloat {
        min(Config3D.baseBallSpeed + CGFloat(levelIndex) * Config3D.speedPerLevel,
            Config3D.maxBallSpeed)
    }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        addChild(gameNode)
        drawTunnel()
        buildBricks()
        setupPaddle()
        setupDepthRing()
        setupHUD()
        spawnServingBall()
    }

    private func drawTunnel() {
        let lineColor = SKColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1)

        // rear wall fill
        let rear = Tunnel.crossSection(at: Tunnel.depth, in: size)
        let rearPath = CGMutablePath()
        rearPath.addLines(between: rear)
        rearPath.closeSubpath()
        let rearWall = SKShapeNode(path: rearPath)
        rearWall.fillColor = SKColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 1)
        rearWall.strokeColor = lineColor.withAlphaComponent(0.35)
        rearWall.lineWidth = 1
        rearWall.zPosition = 2000 - Tunnel.depth - 20
        addChild(rearWall)

        // depth rings, fading toward the rear
        var z: CGFloat = 0
        while z <= Tunnel.depth {
            let pts = Tunnel.crossSection(at: z, in: size)
            let path = CGMutablePath()
            path.addLines(between: pts)
            path.closeSubpath()
            let ring = SKShapeNode(path: path)
            ring.strokeColor = lineColor.withAlphaComponent(z == 0 ? 0.5 : 0.13)
            ring.lineWidth = z == 0 ? 2 : 1
            ring.zPosition = 2000 - z - 10
            addChild(ring)
            z += 200
        }

        // corner rails from the front plane to the rear wall
        let front = Tunnel.crossSection(at: 0, in: size)
        for i in 0..<4 {
            let path = CGMutablePath()
            path.move(to: front[i])
            path.addLine(to: rear[i])
            let rail = SKShapeNode(path: path)
            rail.strokeColor = lineColor.withAlphaComponent(0.25)
            rail.lineWidth = 1
            rail.zPosition = 2000 - Tunnel.depth - 15
            addChild(rail)
        }
    }

    private func buildBricks() {
        let layers = Levels3D.all[levelIndex]
        let cellW = Tunnel.width / CGFloat(Config3D.brickColumns)
        let cellH = Tunnel.height / CGFloat(Config3D.brickRows)
        let gapX: CGFloat = 8
        let gapY: CGFloat = 12

        for (layerIndex, rows) in layers.enumerated() {
            // rearmost layer sits just in front of the rear wall
            let zBack = Tunnel.depth - Config3D.rearGap
                - CGFloat(layers.count - 1 - layerIndex) * Config3D.layerSpacing
            let zFront = zBack - Config3D.brickThickness

            for (rowIndex, row) in rows.enumerated() {
                for (colIndex, char) in row.enumerated() where colIndex < Config3D.brickColumns {
                    let xMin = -Tunnel.halfW + CGFloat(colIndex) * cellW + gapX / 2
                    let yMax = Tunnel.halfH - CGFloat(rowIndex) * cellH - gapY / 2
                    let boxMin = Vec3(x: xMin, y: yMax - (cellH - gapY), z: zFront)
                    let boxMax = Vec3(x: xMin + cellW - gapX, y: yMax, z: zBack)
                    guard let brick = Brick3D.make(from: char, boxMin: boxMin,
                                                   boxMax: boxMax, sceneSize: size) else { continue }
                    bricks.append(brick)
                    gameNode.addChild(brick.node)
                }
            }
        }
    }

    private func setupPaddle() {
        let pane = SKShapeNode(rectOf: Config3D.paddleSize, cornerRadius: 10)
        pane.fillColor = SKColor(red: 0.82, green: 0.84, blue: 0.90, alpha: 0.22)
        pane.strokeColor = SKColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 0.9)
        pane.lineWidth = 2.5
        pane.zPosition = 2100 // in front of everything in the tunnel
        addChild(pane)
        paddleNode = pane
        paddleXY = .zero
        syncPaddleNode()
    }

    private func setupDepthRing() {
        let ring = SKShapeNode()
        ring.strokeColor = SKColor.white.withAlphaComponent(0.30)
        ring.lineWidth = 1
        addChild(ring)
        depthRing = ring
    }

    private func setupHUD() {
        let hudY = size.height - 44

        let score = SKLabelNode(fontNamed: "AvenirNext-Bold")
        score.fontSize = 24
        score.fontColor = .white
        score.horizontalAlignmentMode = .left
        score.position = CGPoint(x: 24, y: hudY)
        score.zPosition = 5000
        addChild(score)
        scoreLabel = score

        let level = SKLabelNode(fontNamed: "AvenirNext-Bold")
        level.fontSize = 24
        level.fontColor = SKColor.white.withAlphaComponent(0.6)
        level.text = "LEVEL \(levelIndex + 1) · 3D"
        level.position = CGPoint(x: size.width / 2, y: hudY)
        level.zPosition = 5000
        addChild(level)

        let livesNode = SKLabelNode(fontNamed: "AvenirNext-Bold")
        livesNode.fontSize = 24
        livesNode.fontColor = SKColor(red: 0.89, green: 0.24, blue: 0.24, alpha: 1)
        livesNode.horizontalAlignmentMode = .right
        livesNode.position = CGPoint(x: size.width - 80, y: hudY)
        livesNode.zPosition = 5000
        addChild(livesNode)
        livesLabel = livesNode

        let pause = SKLabelNode(fontNamed: "AvenirNext-Bold")
        pause.name = "pauseButton"
        pause.text = "❚❚"
        pause.fontSize = 24
        pause.fontColor = SKColor.white.withAlphaComponent(0.7)
        pause.horizontalAlignmentMode = .right
        pause.position = CGPoint(x: size.width - 24, y: hudY)
        pause.zPosition = 5000
        addChild(pause)

        refreshHUD()
    }

    private func refreshHUD() {
        scoreLabel?.text = "SCORE \(score)"
        livesLabel?.text = String(repeating: "♥", count: max(0, lives))
    }

    // MARK: - Serving

    private func spawnServingBall() {
        let ball = SKShapeNode(circleOfRadius: Config3D.ballRadius)
        ball.fillColor = SKColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
        ball.strokeColor = .clear
        addChild(ball)
        ballNode = ball
        ballInPlay = false
        ballPos = Vec3(x: paddleXY.x, y: paddleXY.y, z: Config3D.ballRadius + 6)
        ballVel = .zero
        syncBallNode()

        let hint = SKLabelNode(fontNamed: "AvenirNext-Bold")
        hint.text = "DRAG TO MOVE · TAP TO LAUNCH"
        hint.fontSize = 22
        hint.fontColor = SKColor.white.withAlphaComponent(0.8)
        hint.position = CGPoint(x: size.width / 2, y: 60)
        hint.zPosition = 5000
        hint.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.25, duration: 0.6),
            SKAction.fadeAlpha(to: 0.8, duration: 0.6),
        ])))
        addChild(hint)
        hintLabel = hint
    }

    private func launchBall() {
        guard !ballInPlay else { return }
        ballInPlay = true
        let dir = Vec3(x: CGFloat.random(in: -0.25...0.25),
                       y: CGFloat.random(in: -0.25...0.25),
                       z: 1).normalized()
        ballVel = dir * targetBallSpeed
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
            movePaddle(toSceneLocation: location)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = controlTouch, touches.contains(touch), !isGamePaused else { return }
        let location = touch.location(in: self)
        let previous = touch.previousLocation(in: self)
        touchMovedDistance += abs(location.x - previous.x) + abs(location.y - previous.y)
        movePaddle(toSceneLocation: location)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = controlTouch, touches.contains(touch) else { return }
        controlTouch = nil
        if !isGamePaused, !ballInPlay, touchMovedDistance < 12 {
            launchBall()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = controlTouch, touches.contains(touch) { controlTouch = nil }
    }

    private func movePaddle(toSceneLocation location: CGPoint) {
        // front plane projects 1:1, so scene coords map directly to world x/y
        let worldX = location.x - size.width / 2
        let worldY = location.y - size.height / 2
        let maxX = Tunnel.halfW - Config3D.paddleSize.width / 2
        let maxY = Tunnel.halfH - Config3D.paddleSize.height / 2
        paddleXY = CGPoint(x: min(max(worldX, -maxX), maxX),
                           y: min(max(worldY, -maxY), maxY))
        syncPaddleNode()
        if !ballInPlay {
            ballPos = Vec3(x: paddleXY.x, y: paddleXY.y, z: Config3D.ballRadius + 6)
            syncBallNode()
        }
    }

    private func syncPaddleNode() {
        paddleNode?.position = CGPoint(x: size.width / 2 + paddleXY.x,
                                       y: size.height / 2 + paddleXY.y)
    }

    // MARK: - Pause

    private func setPaused(_ paused: Bool) {
        isGamePaused = paused
        gameNode.isPaused = paused

        if paused {
            let overlay = SKNode()
            overlay.zPosition = 6000

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
        defer { lastUpdateTime = currentTime }
        guard lastUpdateTime > 0 else { return }
        guard !isGamePaused, !isTransitioning else { return }
        let dt = CGFloat(min(currentTime - lastUpdateTime, 1.0 / 30.0))

        if ballInPlay {
            stepBall(dt: dt)
        }
        syncBallNode()
        syncDepthRing()
    }

    private func stepBall(dt: CGFloat) {
        let r = Config3D.ballRadius
        ballPos = ballPos + ballVel * dt

        // side walls
        if ballPos.x - r < -Tunnel.halfW {
            ballPos.x = -Tunnel.halfW + r
            ballVel.x = abs(ballVel.x)
            SoundPlayer.play(.wallHit, on: self)
        } else if ballPos.x + r > Tunnel.halfW {
            ballPos.x = Tunnel.halfW - r
            ballVel.x = -abs(ballVel.x)
            SoundPlayer.play(.wallHit, on: self)
        }
        if ballPos.y - r < -Tunnel.halfH {
            ballPos.y = -Tunnel.halfH + r
            ballVel.y = abs(ballVel.y)
            SoundPlayer.play(.wallHit, on: self)
        } else if ballPos.y + r > Tunnel.halfH {
            ballPos.y = Tunnel.halfH - r
            ballVel.y = -abs(ballVel.y)
            SoundPlayer.play(.wallHit, on: self)
        }

        // rear wall
        if ballPos.z + r > Tunnel.depth {
            ballPos.z = Tunnel.depth - r
            ballVel.z = -abs(ballVel.z)
            SoundPlayer.play(.wallHit, on: self)
        }

        // paddle plane
        if ballVel.z < 0, ballPos.z - r <= 0, ballPos.z - r > -40 {
            let halfW = Config3D.paddleSize.width / 2
            let halfH = Config3D.paddleSize.height / 2
            if abs(ballPos.x - paddleXY.x) <= halfW + r,
               abs(ballPos.y - paddleXY.y) <= halfH + r {
                let nx = min(max((ballPos.x - paddleXY.x) / halfW, -1), 1)
                let ny = min(max((ballPos.y - paddleXY.y) / halfH, -1), 1)
                ballPos.z = r
                ballVel = Vec3(x: nx * 0.8, y: ny * 0.8, z: 1).normalized() * targetBallSpeed
                SoundPlayer.play(.paddleHit, on: self)
                SoundPlayer.tapHaptic()
                paddleNode?.run(SKAction.sequence([
                    SKAction.scale(to: 1.08, duration: 0.05),
                    SKAction.scale(to: 1.0, duration: 0.08),
                ]))
            }
        }

        // missed: ball escaped past the paddle plane
        if ballPos.z < Config3D.lossDepth {
            ballLost()
            return
        }

        // bricks
        collideWithBricks()

        // keep speed constant, and keep a healthy z component
        var v = ballVel
        let speed = v.length
        if speed > 0 {
            v = v * (targetBallSpeed / speed)
            let minVz = Config3D.minDepthFraction * targetBallSpeed
            if abs(v.z) < minVz {
                let sign: CGFloat = v.z >= 0 ? 1 : -1
                let lateral = sqrt(max(0, 1 - Config3D.minDepthFraction * Config3D.minDepthFraction))
                let planar = sqrt(v.x * v.x + v.y * v.y)
                if planar > 0 {
                    let k = targetBallSpeed * lateral / planar
                    v = Vec3(x: v.x * k, y: v.y * k, z: sign * minVz)
                } else {
                    v = Vec3(x: 0, y: 0, z: sign * targetBallSpeed)
                }
            }
            ballVel = v
        }
    }

    private func collideWithBricks() {
        let r = Config3D.ballRadius
        for brick in bricks where brick.isAlive {
            let qx = min(max(ballPos.x, brick.boxMin.x), brick.boxMax.x)
            let qy = min(max(ballPos.y, brick.boxMin.y), brick.boxMax.y)
            let qz = min(max(ballPos.z, brick.boxMin.z), brick.boxMax.z)
            let dx = ballPos.x - qx
            let dy = ballPos.y - qy
            let dz = ballPos.z - qz
            let d2 = dx * dx + dy * dy + dz * dz
            guard d2 <= r * r else { continue }

            // reflect along the dominant axis of the contact normal
            let adx = abs(dx), ady = abs(dy), adz = abs(dz)
            if adz >= adx, adz >= ady, adz > 0 {
                ballVel.z = dz > 0 ? abs(ballVel.z) : -abs(ballVel.z)
                ballPos.z = qz + (dz > 0 ? r : -r)
            } else if adx >= ady, adx > 0 {
                ballVel.x = dx > 0 ? abs(ballVel.x) : -abs(ballVel.x)
                ballPos.x = qx + (dx > 0 ? r : -r)
            } else if ady > 0 {
                ballVel.y = dy > 0 ? abs(ballVel.y) : -abs(ballVel.y)
                ballPos.y = qy + (dy > 0 ? r : -r)
            } else {
                // ball center exactly on the box surface: push straight back
                ballVel.z = -ballVel.z
            }
            hitBrick(brick)
            break
        }
    }

    private func hitBrick(_ brick: Brick3D) {
        if brick.takeHit() {
            score += brick.pointValue
            refreshHUD()
            spawnFragments(for: brick)
            brick.node.removeFromParent()
            SoundPlayer.play(.brickBreak, on: self)
            SoundPlayer.breakHaptic()
            checkLevelCleared()
        } else if brick.isIndestructible {
            SoundPlayer.play(.wallHit, on: self)
        } else {
            SoundPlayer.play(.brickHit, on: self)
        }
    }

    private func spawnFragments(for brick: Brick3D) {
        let center = brick.center
        let origin = Tunnel.project(center, in: size)
        let depthScale = Tunnel.scale(at: center.z)
        for _ in 0..<6 {
            let fragment = SKSpriteNode(color: brick.color,
                                        size: CGSize(width: 7 * depthScale, height: 7 * depthScale))
            fragment.position = origin
            fragment.zPosition = 2000 - brick.boxMin.z + 1
            gameNode.addChild(fragment)
            let dx = CGFloat.random(in: -70...70) * depthScale
            let dy = CGFloat.random(in: -40...90) * depthScale
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

    // MARK: - Node syncing

    private func syncBallNode() {
        guard let node = ballNode else { return }
        node.position = Tunnel.project(ballPos, in: size)
        node.setScale(Tunnel.scale(at: max(ballPos.z, 0)))
        node.zPosition = 2000 - ballPos.z + 5
    }

    private func syncDepthRing() {
        guard let ring = depthRing else { return }
        guard ballInPlay, ballPos.z > 0 else {
            ring.path = nil
            return
        }
        let pts = Tunnel.crossSection(at: ballPos.z, in: size)
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        ring.path = path
        ring.zPosition = 2000 - ballPos.z + 2
        // brighter as the ball approaches the player — that's when it matters
        ring.strokeColor = SKColor.white.withAlphaComponent(
            0.12 + 0.30 * Tunnel.scale(at: ballPos.z))
    }

    // MARK: - Losing / winning

    private func ballLost() {
        ballNode?.removeFromParent()
        ballNode = nil
        ballVel = .zero
        ballInPlay = false

        lives -= 1
        refreshHUD()
        SoundPlayer.play(.loseLife, on: self)
        SoundPlayer.failureHaptic()

        if lives <= 0 {
            gameOver(didWin: false)
        } else {
            spawnServingBall()
        }
    }

    private func checkLevelCleared() {
        let remaining = bricks.contains { $0.isAlive && !$0.isIndestructible }
        guard !remaining else { return }
        isTransitioning = true
        ballVel = .zero
        SoundPlayer.play(.levelClear, on: self)
        SoundPlayer.successHaptic()

        let banner = SKLabelNode(fontNamed: "AvenirNext-Bold")
        banner.text = "LEVEL \(levelIndex + 1) CLEARED!"
        banner.fontSize = 44
        banner.fontColor = .white
        banner.setScale(0.1)
        banner.position = CGPoint(x: size.width / 2, y: size.height / 2)
        banner.zPosition = 5000
        addChild(banner)
        banner.run(SKAction.scale(to: 1.0, duration: 0.3))

        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.4),
            SKAction.run { [weak self] in self?.advance() },
        ]))
    }

    private func advance() {
        if levelIndex + 1 >= Levels3D.all.count {
            gameOver(didWin: true)
        } else {
            let next = GameScene3D(levelIndex: levelIndex + 1, score: score, lives: lives)
            view?.presentScene(next, transition: .doorway(withDuration: 0.6))
        }
    }

    private func gameOver(didWin: Bool) {
        isTransitioning = true
        let scene = GameOverScene(score: score, didWin: didWin, mode: .tunnel3D)
        view?.presentScene(scene, transition: .fade(withDuration: 0.6))
    }
}
