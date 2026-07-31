import SpriteKit
import UIKit

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

    private var ballNode: SKSpriteNode?
    private var ballHighlight: SKShapeNode?
    /// Shadows cast on floor, ceiling, left and right walls (in that order).
    private var wallShadows: [SKShapeNode] = []
    private var aimShadow: SKShapeNode?
    private var paddleNode: SKNode?
    private var paddleFront: SKShapeNode?
    private var paddleBack: SKShapeNode?
    private var paddleRails: SKShapeNode?
    private var paddleZ: CGFloat = 0
    private var pinchStartZ: CGFloat = 0
    private var lastPinchZone = 0
    private var pinchRecognizer: UIPinchGestureRecognizer?
    private var paddleShadow: SKShapeNode?
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
        setupBallShadows()
        setupHUD()
        spawnServingBall()

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        pinchRecognizer = pinch
    }

    override func willMove(from view: SKView) {
        if let pinch = pinchRecognizer {
            view.removeGestureRecognizer(pinch)
            pinchRecognizer = nil
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard !isGamePaused, !isTransitioning else { return }
        switch recognizer.state {
        case .began:
            pinchStartZ = paddleZ
            controlTouch = nil // two fingers down: stop treating either as a drag
        case .changed:
            // pinch in pushes the paddle into the tunnel, pinch out pulls it back
            let candidate = pinchStartZ - (recognizer.scale - 1) * Config3D.pinchSensitivity
            paddleZ = min(max(candidate, 0), Config3D.maxPaddleZ)
            syncPaddleNode()
            if !ballInPlay {
                ballPos = Vec3(x: paddleXY.x, y: paddleXY.y, z: servingBallZ)
                syncBallNode()
            }
            // sonar-style feedback: rising blips as the paddle recedes,
            // falling blips as it comes back toward the player
            let zoneWidth = Config3D.maxPaddleZ / CGFloat(Config3D.pinchZones)
            let zone = min(Config3D.pinchZones - 1, max(0, Int(paddleZ / zoneWidth)))
            if zone != lastPinchZone {
                SoundPlayer.play(Sound.pinchScale[zone], on: self)
                lastPinchZone = zone
            }
        default:
            break
        }
    }

    /// Resting z of a served ball, just in front of the paddle slab.
    private var servingBallZ: CGFloat {
        paddleZ + Config3D.paddleDepth + Config3D.ballRadius + 2
    }

    /// A wall drawn as one texture with a real linear gradient along the
    /// depth axis — smooth shading, no banding.
    private func gradientWall(_ points: [CGPoint], from nearColor: UIColor, to farColor: UIColor,
                              start: CGPoint, end: CGPoint) {
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let bbox = CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
        // scene y-up → UIKit y-down
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - bbox.minX, y: bbox.maxY - p.y) }

        let renderer = UIGraphicsImageRenderer(size: bbox.size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let path = CGMutablePath()
            path.addLines(between: points.map(flip))
            path.closeSubpath()
            cg.addPath(path)
            cg.clip()
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [nearColor.cgColor, farColor.cgColor] as CFArray,
                                            locations: [0, 1]) else { return }
            cg.drawLinearGradient(gradient, start: flip(start), end: flip(end),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.position = CGPoint(x: bbox.midX, y: bbox.midY)
        sprite.zPosition = 700 // behind everything that lives in the tunnel
        addChild(sprite)
    }

    private func drawTunnel() {
        let lineColor = SKColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1)

        // rear wall: a distinct deep indigo so the brick walls stand out
        // against it, darker than anything at the front (light comes from
        // the player's end of the tunnel)
        let rear = Tunnel.crossSection(at: Tunnel.depth, in: size)
        let rearPath = CGMutablePath()
        rearPath.addLines(between: rear)
        rearPath.closeSubpath()
        let rearWall = SKShapeNode(path: rearPath)
        rearWall.fillColor = SKColor(red: 0.11, green: 0.08, blue: 0.22, alpha: 1)
        rearWall.strokeColor = lineColor.withAlphaComponent(0.35)
        rearWall.lineWidth = 1
        rearWall.zPosition = 2000 - Tunnel.depth - 20
        addChild(rearWall)

        // side walls: slate-blue with a single smooth gradient per wall,
        // bright at the front opening and falling off into the depth; the
        // floor catches the most light, the ceiling the least
        let wallBase = (r: CGFloat(0.20), g: CGFloat(0.26), b: CGFloat(0.38))
        func wallColor(_ faceLight: CGFloat, _ depthShade: CGFloat) -> UIColor {
            UIColor(red: wallBase.r * depthShade * faceLight,
                    green: wallBase.g * depthShade * faceLight,
                    blue: wallBase.b * depthShade * faceLight,
                    alpha: 1)
        }
        // crossSection corner order: 0 bottom-left, 1 bottom-right, 2 top-right, 3 top-left
        let front = Tunnel.crossSection(at: 0, in: size)
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        let nearShade: CGFloat = 0.95
        let farShade: CGFloat = 0.20
        // floor
        gradientWall([front[0], front[1], rear[1], rear[0]],
                     from: wallColor(1.15, nearShade), to: wallColor(1.15, farShade),
                     start: mid(front[0], front[1]), end: mid(rear[0], rear[1]))
        // ceiling
        gradientWall([front[3], front[2], rear[2], rear[3]],
                     from: wallColor(0.62, nearShade), to: wallColor(0.62, farShade),
                     start: mid(front[3], front[2]), end: mid(rear[3], rear[2]))
        // left wall
        gradientWall([front[0], front[3], rear[3], rear[0]],
                     from: wallColor(0.88, nearShade), to: wallColor(0.88, farShade),
                     start: mid(front[0], front[3]), end: mid(rear[0], rear[3]))
        // right wall
        gradientWall([front[1], front[2], rear[2], rear[1]],
                     from: wallColor(0.88, nearShade), to: wallColor(0.88, farShade),
                     start: mid(front[1], front[2]), end: mid(rear[1], rear[2]))

        // depth rings, fading toward the rear
        var z: CGFloat = 0
        while z <= Tunnel.depth {
            let pts = Tunnel.crossSection(at: z, in: size)
            let path = CGMutablePath()
            path.addLines(between: pts)
            path.closeSubpath()
            let ring = SKShapeNode(path: path)
            ring.strokeColor = lineColor.withAlphaComponent(z == 0 ? 0.65 : 0.13)
            ring.lineWidth = z == 0 ? 2.5 : 1
            ring.zPosition = 2000 - z - 10
            addChild(ring)
            z += 200
        }

        // corner rails from the front plane to the rear wall
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

        for (layerIndex, rows) in layers.enumerated() {
            // grid size comes from the map: fewer cells = bigger bricks
            let columns = rows.first?.count ?? 1
            let cellW = Tunnel.width / CGFloat(columns)
            let cellH = Tunnel.height / CGFloat(rows.count)
            let gapX = cellW * 0.07
            let gapY = cellH * 0.12

            // rearmost layer sits just in front of the rear wall
            let zBack = Tunnel.depth - Config3D.rearGap
                - CGFloat(layers.count - 1 - layerIndex) * Config3D.layerSpacing
            let zFront = zBack - Config3D.brickThickness

            for (rowIndex, row) in rows.enumerated() {
                for (colIndex, char) in row.enumerated() where colIndex < columns {
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
        // The paddle is a translucent 3D slab: a back pane deeper in the
        // tunnel, a front pane at z = 0, and rails joining their corners.
        // The parallax between the two panes as it moves sells the depth.
        let container = SKNode()
        container.zPosition = 2100 // in front of everything in the tunnel

        let back = SKShapeNode()
        back.fillColor = SKColor(red: 0.82, green: 0.84, blue: 0.90, alpha: 0.16)
        back.strokeColor = SKColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 0.95)
        back.lineWidth = 2
        back.zPosition = 0
        container.addChild(back)
        paddleBack = back

        let rails = SKShapeNode()
        rails.strokeColor = SKColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 0.55)
        rails.lineWidth = 1.5
        rails.zPosition = 1
        container.addChild(rails)
        paddleRails = rails

        let front = SKShapeNode()
        front.fillColor = SKColor(red: 0.82, green: 0.84, blue: 0.90, alpha: 0.10)
        front.strokeColor = SKColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 0.6)
        front.lineWidth = 2
        front.zPosition = 2
        container.addChild(front)
        paddleFront = front

        addChild(container)
        paddleNode = container

        // shadow the paddle casts on whichever wall it is closest to;
        // the path is rebuilt each frame as a perspective-correct footprint
        let shadow = SKShapeNode()
        shadow.fillColor = SKColor.black.withAlphaComponent(0.7)
        shadow.strokeColor = .clear
        addChild(shadow)
        paddleShadow = shadow

        paddleXY = .zero
        syncPaddleNode()
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func setupBallShadows() {
        // one soft shadow per wall: floor, ceiling, left, right — as if lit
        // from every wall, so each shadow tells you the distance to that wall
        let r = Config3D.ballRadius
        let horizontal = CGSize(width: r * 2.9, height: r * 1.1) // floor/ceiling
        let vertical = CGSize(width: r * 1.1, height: r * 2.9)   // left/right walls
        wallShadows = [horizontal, horizontal, vertical, vertical].map { size in
            let shadow = SKShapeNode(ellipseOf: size)
            shadow.fillColor = SKColor.black.withAlphaComponent(0.8)
            shadow.strokeColor = .clear
            shadow.isHidden = true
            addChild(shadow)
            return shadow
        }

        // shadow that fades in on the paddle plane as the ball approaches —
        // line this up with the paddle and the catch is yours
        let aim = SKShapeNode(circleOfRadius: r * 1.15)
        aim.fillColor = SKColor.black.withAlphaComponent(0.6)
        aim.strokeColor = SKColor.white.withAlphaComponent(0.25)
        aim.lineWidth = 1
        aim.isHidden = true
        addChild(aim)
        aimShadow = aim
    }

    /// Pre-rendered radial-gradient sphere: white specular core offset to the
    /// upper left, rolling off through the body color into a dark limb.
    private static func makeSphereTexture(radius: CGFloat) -> SKTexture {
        let d = radius * 4 // 2x for retina crispness
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor.white.cgColor,
                UIColor(white: 0.93, alpha: 1).cgColor,
                UIColor(white: 0.62, alpha: 1).cgColor,
                UIColor(white: 0.22, alpha: 1).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.25, 0.72, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: locations) else { return }
            cg.addEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
            cg.clip()
            cg.drawRadialGradient(gradient,
                                  startCenter: CGPoint(x: d * 0.36, y: d * 0.33),
                                  startRadius: 0,
                                  endCenter: CGPoint(x: d * 0.46, y: d * 0.45),
                                  endRadius: d * 0.68,
                                  options: [.drawsAfterEndLocation])
        }
        return SKTexture(image: image)
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
        let r = Config3D.ballRadius
        let ball = SKSpriteNode(texture: GameScene3D.makeSphereTexture(radius: r),
                                size: CGSize(width: r * 2, height: r * 2))

        // small extra specular dot that slides with the ball's position in
        // the tunnel, so the lighting reads as live rather than painted on
        let highlight = SKShapeNode(circleOfRadius: r * 0.16)
        highlight.fillColor = SKColor.white.withAlphaComponent(0.85)
        highlight.strokeColor = .clear
        highlight.zPosition = 1
        ball.addChild(highlight)
        ballHighlight = highlight

        addChild(ball)
        ballNode = ball
        ballInPlay = false
        ballPos = Vec3(x: paddleXY.x, y: paddleXY.y, z: servingBallZ)
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
        // inverse-project the touch through the paddle's current depth: the
        // deeper the paddle, the more world distance one finger-point covers,
        // so a deep paddle is smaller on screen but faster to steer
        let s = Tunnel.scale(at: paddleZ)
        let worldX = (location.x - size.width / 2) / s
        let worldY = (location.y - size.height / 2 - Tunnel.centerYOffset) / s
        let maxX = Tunnel.halfW - Config3D.paddleSize.width / 2
        let maxY = Tunnel.halfH - Config3D.paddleSize.height / 2
        paddleXY = CGPoint(x: min(max(worldX, -maxX), maxX),
                           y: min(max(worldY, -maxY), maxY))
        syncPaddleNode()
        if !ballInPlay {
            ballPos = Vec3(x: paddleXY.x, y: paddleXY.y, z: servingBallZ)
            syncBallNode()
        }
    }

    private func syncPaddleNode() {
        let hw = Config3D.paddleSize.width / 2
        let hh = Config3D.paddleSize.height / 2
        let zFront = paddleZ
        let zBack = paddleZ + Config3D.paddleDepth
        func pt(_ dx: CGFloat, _ dy: CGFloat, _ z: CGFloat) -> CGPoint {
            Tunnel.project(Vec3(x: paddleXY.x + dx, y: paddleXY.y + dy, z: z), in: size)
        }
        let f = [pt(-hw, -hh, zFront), pt(hw, -hh, zFront), pt(hw, hh, zFront), pt(-hw, hh, zFront)]
        let b = [pt(-hw, -hh, zBack), pt(hw, -hh, zBack), pt(hw, hh, zBack), pt(-hw, hh, zBack)]
        paddleFront?.path = Draw.roundedPolygon(f, radius: 22 * Tunnel.scale(at: zFront))
        paddleBack?.path = Draw.roundedPolygon(b, radius: 22 * Tunnel.scale(at: zBack))

        // rails pull in slightly toward each pane's center so their endpoints
        // land inside the rounded corners instead of poking past them
        let fc = Tunnel.project(Vec3(x: paddleXY.x, y: paddleXY.y, z: zFront), in: size)
        let bc = Tunnel.project(Vec3(x: paddleXY.x, y: paddleXY.y, z: zBack), in: size)
        let rails = CGMutablePath()
        for i in 0..<4 {
            rails.move(to: GameScene3D.lerp(f[i], fc, 0.10))
            rails.addLine(to: GameScene3D.lerp(b[i], bc, 0.10))
        }
        paddleRails?.path = rails

        // stay correctly sorted against the ball and walls at this depth
        paddleNode?.zPosition = 2000 - paddleZ + 8

        syncPaddleShadow()
    }

    /// The paddle casts one shadow, on the nearest wall: the closer it gets,
    /// the darker and larger the shadow — a live proximity gauge. The shadow
    /// is the paddle's actual footprint projected onto that wall (a
    /// perspective-correct rounded trapezoid), not a generic blob.
    private func syncPaddleShadow() {
        guard let shadow = paddleShadow else { return }
        let z0 = paddleZ - 12
        let z1 = paddleZ + Config3D.paddleDepth + 12
        let zMid = paddleZ + Config3D.paddleDepth / 2
        let distances: [CGFloat] = [
            paddleXY.y + Tunnel.halfH,  // floor
            Tunnel.halfH - paddleXY.y,  // ceiling
            paddleXY.x + Tunnel.halfW,  // left wall
            Tunnel.halfW - paddleXY.x,  // right wall
        ]
        var wall = 0
        for i in 1..<4 where distances[i] < distances[wall] { wall = i }

        let halfSpan = wall < 2 ? Tunnel.halfH : Tunnel.halfW
        let proximity = 1 - min(distances[wall] / halfSpan, 1) // 1 at the wall, 0 at center
        let inflate = 1.0 + 0.5 * proximity // shadow grows as the paddle closes in

        // paddle footprint on the wall, in world space
        let corners: [Vec3]
        switch wall {
        case 0, 1: // floor or ceiling: width x slab-depth footprint
            let hw = Config3D.paddleSize.width / 2 * inflate
            let wallY: CGFloat = wall == 0 ? -Tunnel.halfH : Tunnel.halfH
            corners = [
                Vec3(x: paddleXY.x - hw, y: wallY, z: z0),
                Vec3(x: paddleXY.x + hw, y: wallY, z: z0),
                Vec3(x: paddleXY.x + hw, y: wallY, z: z1),
                Vec3(x: paddleXY.x - hw, y: wallY, z: z1),
            ]
        default: // side walls: height x slab-depth footprint
            let hh = Config3D.paddleSize.height / 2 * inflate
            let wallX: CGFloat = wall == 2 ? -Tunnel.halfW : Tunnel.halfW
            corners = [
                Vec3(x: wallX, y: paddleXY.y - hh, z: z0),
                Vec3(x: wallX, y: paddleXY.y + hh, z: z0),
                Vec3(x: wallX, y: paddleXY.y + hh, z: z1),
                Vec3(x: wallX, y: paddleXY.y - hh, z: z1),
            ]
        }
        let projected = corners.map { Tunnel.project($0, in: size) }
        shadow.path = Draw.roundedPolygon(projected, radius: 14 * Tunnel.scale(at: zMid))
        shadow.isHidden = false
        shadow.alpha = 0.15 + 0.55 * proximity
        shadow.zPosition = 2000 - zMid - 25
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

        // paddle slab: the ball bounces off its tunnel-facing pane, wherever
        // the pinch gesture has parked it in z
        let paddlePlane = paddleZ + Config3D.paddleDepth
        if ballVel.z < 0, ballPos.z - r <= paddlePlane, ballPos.z - r > paddlePlane - 40 {
            let halfW = Config3D.paddleSize.width / 2
            let halfH = Config3D.paddleSize.height / 2
            if abs(ballPos.x - paddleXY.x) <= halfW + r,
               abs(ballPos.y - paddleXY.y) <= halfH + r {
                let nx = min(max((ballPos.x - paddleXY.x) / halfW, -1), 1)
                let ny = min(max((ballPos.y - paddleXY.y) / halfH, -1), 1)
                ballPos.z = paddlePlane + r
                ballVel = Vec3(x: nx * 0.8, y: ny * 0.8, z: 1).normalized() * targetBallSpeed
                SoundPlayer.play(.paddleHit, on: self)
                SoundPlayer.tapHaptic()
                paddleNode?.run(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.5, duration: 0.05),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.10),
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
            // brick survived and cracked — distinct snap, not the generic blip
            SoundPlayer.play(.crack, on: self)
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
        guard let node = ballNode else {
            wallShadows.forEach { $0.isHidden = true }
            aimShadow?.isHidden = true
            return
        }
        let r = Config3D.ballRadius
        let depthScale = Tunnel.scale(at: max(ballPos.z, 0))
        node.position = Tunnel.project(ballPos, in: size)
        node.setScale(depthScale)
        node.zPosition = 2000 - ballPos.z + 5

        // darker when deep in the tunnel, bright when near the player
        let brightness = 0.45 + 0.55 * depthScale
        node.color = .black
        node.colorBlendFactor = (1 - brightness) * 0.75

        // the specular dot drifts opposite the ball's offset from the tunnel
        // axis — as if lit from the front center — making the shading dynamic
        if let highlight = ballHighlight {
            highlight.position = CGPoint(
                x: -r * 0.28 - (ballPos.x / Tunnel.halfW) * r * 0.22,
                y: r * 0.30 - (ballPos.y / Tunnel.halfH) * r * 0.22)
            highlight.alpha = 0.35 + 0.55 * depthScale
        }

        syncWallShadows(depthScale: depthScale)
        syncAimShadow()
    }

    /// One cast shadow per wall; each grows softer with distance from its
    /// wall and tighter/darker as the ball closes in — a live 3D crosshair.
    private func syncWallShadows(depthScale: CGFloat) {
        guard wallShadows.count == 4 else { return }
        let anchors: [Vec3] = [
            Vec3(x: ballPos.x, y: -Tunnel.halfH, z: ballPos.z), // floor
            Vec3(x: ballPos.x, y: Tunnel.halfH, z: ballPos.z),  // ceiling
            Vec3(x: -Tunnel.halfW, y: ballPos.y, z: ballPos.z), // left wall
            Vec3(x: Tunnel.halfW, y: ballPos.y, z: ballPos.z),  // right wall
        ]
        let distances: [CGFloat] = [
            ballPos.y + Tunnel.halfH,
            Tunnel.halfH - ballPos.y,
            ballPos.x + Tunnel.halfW,
            Tunnel.halfW - ballPos.x,
        ]
        let spans: [CGFloat] = [Tunnel.height, Tunnel.height, Tunnel.width, Tunnel.width]
        for i in 0..<4 {
            let shadow = wallShadows[i]
            shadow.isHidden = false
            shadow.position = Tunnel.project(anchors[i], in: size)
            let spread = 1 + distances[i] / 900
            shadow.setScale(depthScale * spread)
            shadow.alpha = max(0.16, 0.72 - distances[i] / spans[i] * 0.55)
            shadow.zPosition = 2000 - ballPos.z - 25
        }
    }

    /// Fades in on the paddle's bounce plane while the ball approaches.
    private func syncAimShadow() {
        guard let aim = aimShadow else { return }
        let plane = paddleZ + Config3D.paddleDepth
        guard ballInPlay, ballVel.z < 0, ballPos.z > plane else {
            aim.isHidden = true
            return
        }
        let closeness = 1 - (ballPos.z - plane) / 700
        guard closeness > 0 else {
            aim.isHidden = true
            return
        }
        aim.isHidden = false
        aim.position = Tunnel.project(Vec3(x: ballPos.x, y: ballPos.y, z: plane), in: size)
        aim.setScale(Tunnel.scale(at: plane))
        aim.alpha = 0.65 * closeness
        aim.zPosition = 2000 - plane + 9
    }

    // MARK: - Losing / winning

    private func ballLost() {
        ballNode?.removeFromParent()
        ballNode = nil
        ballHighlight = nil
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
