import SpriteKit

/// A 3D brick: an axis-aligned box in tunnel space plus its pre-rendered
/// projected node (front face, back face, and the sides that face the camera).
/// Multi-hit bricks accumulate procedural cracks instead of changing color.
final class Brick3D {
    let boxMin: Vec3
    let boxMax: Vec3
    let pointValue: Int
    let isIndestructible: Bool
    let node: SKNode
    private(set) var hitPoints: Int
    private(set) var isAlive = true

    private let frontPoints: [CGPoint]
    private let frontScale: CGFloat
    private var crackStage = 0

    var center: Vec3 {
        Vec3(x: (boxMin.x + boxMax.x) / 2,
             y: (boxMin.y + boxMax.y) / 2,
             z: (boxMin.z + boxMax.z) / 2)
    }
    let color: SKColor

    private static func style(for char: Character) -> (hp: Int, points: Int, color: SKColor, indestructible: Bool)? {
        // saturated neon palette
        switch char {
        case "1": return (1, 50, SKColor(red: 0.16, green: 0.95, blue: 0.45, alpha: 1), false)
        case "2": return (2, 100, SKColor(red: 0.20, green: 0.62, blue: 1.00, alpha: 1), false)
        case "3": return (3, 150, SKColor(red: 1.00, green: 0.28, blue: 0.42, alpha: 1), false)
        case "X": return (0, 0, SKColor(red: 0.62, green: 0.65, blue: 0.72, alpha: 1), true)
        default: return nil
        }
    }

    static func make(from char: Character, boxMin: Vec3, boxMax: Vec3, sceneSize: CGSize) -> Brick3D? {
        guard let s = style(for: char) else { return nil }
        return Brick3D(boxMin: boxMin, boxMax: boxMax, hp: s.hp, points: s.points,
                       color: s.color, indestructible: s.indestructible, sceneSize: sceneSize)
    }

    private init(boxMin: Vec3, boxMax: Vec3, hp: Int, points: Int,
                 color: SKColor, indestructible: Bool, sceneSize: CGSize) {
        self.boxMin = boxMin
        self.boxMax = boxMax
        self.hitPoints = hp
        self.pointValue = points
        self.color = color
        self.isIndestructible = indestructible
        self.frontPoints = Brick3D.faceCorners(boxMin: boxMin, boxMax: boxMax,
                                               z: boxMin.z, sceneSize: sceneSize)
        self.frontScale = Tunnel.scale(at: boxMin.z)
        self.node = Brick3D.buildNode(boxMin: boxMin, boxMax: boxMax, color: color, sceneSize: sceneSize)
        node.zPosition = 2000 - boxMin.z
    }

    /// Applies one hit. Returns true if the brick was destroyed.
    func takeHit() -> Bool {
        guard !isIndestructible else { return false }
        hitPoints -= 1
        if hitPoints <= 0 {
            isAlive = false
            return true
        }
        crackStage += 1
        addCrack(stage: crackStage)
        node.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05),
        ]))
        return false
    }

    // MARK: - Cracks

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Jagged crack lines radiating from a point near the face center out
    /// toward the edges; each further stage adds more and longer branches.
    private func addCrack(stage: Int) {
        let f = frontPoints
        let centroid = CGPoint(x: (f[0].x + f[1].x + f[2].x + f[3].x) / 4,
                               y: (f[0].y + f[1].y + f[2].y + f[3].y) / 4)
        let jitterScale = 6 * frontScale
        let origin = CGPoint(x: centroid.x + CGFloat.random(in: -jitterScale...jitterScale),
                             y: centroid.y + CGFloat.random(in: -jitterScale...jitterScale))
        let branches = stage == 1 ? 4 : 6
        let reach: CGFloat = stage == 1 ? 0.55 : 0.95

        let path = CGMutablePath()
        for i in 0..<branches {
            // spread branch targets around the perimeter
            let edge = (i + Int.random(in: 0...1)) % 4
            let t = CGFloat.random(in: 0.2...0.8)
            let edgeTarget = Brick3D.lerp(f[edge], f[(edge + 1) % 4], t)
            let target = Brick3D.lerp(origin, edgeTarget, reach)
            path.move(to: origin)
            var previous = origin
            for step in 1...3 {
                var point = Brick3D.lerp(origin, target, CGFloat(step) / 3)
                if step < 3 {
                    point.x += CGFloat.random(in: -jitterScale...jitterScale)
                    point.y += CGFloat.random(in: -jitterScale...jitterScale)
                }
                path.addLine(to: point)
                previous = point
            }
            _ = previous
        }

        let crack = SKShapeNode(path: path)
        crack.strokeColor = SKColor.black.withAlphaComponent(stage == 1 ? 0.5 : 0.65)
        crack.lineWidth = max(1, 1.8 * frontScale)
        crack.lineCap = .round
        crack.lineJoin = .round
        crack.zPosition = 10
        node.addChild(crack)
    }

    // MARK: - Rendering

    private static func shaded(_ color: SKColor, _ factor: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: min(1, r * factor), green: min(1, g * factor),
                       blue: min(1, b * factor), alpha: a)
    }

    private static func quad(_ points: [CGPoint], fill: SKColor, stroke: SKColor,
                             cornerRadius: CGFloat = 0) -> SKShapeNode {
        let shape = SKShapeNode(path: Draw.roundedPolygon(points, radius: cornerRadius))
        shape.fillColor = fill
        shape.strokeColor = stroke
        shape.lineWidth = 1
        shape.lineJoin = .round
        return shape
    }

    private static func faceCorners(boxMin: Vec3, boxMax: Vec3, z: CGFloat,
                                    sceneSize: CGSize) -> [CGPoint] {
        // 0 bottom-left, 1 bottom-right, 2 top-right, 3 top-left
        [
            Tunnel.project(Vec3(x: boxMin.x, y: boxMin.y, z: z), in: sceneSize),
            Tunnel.project(Vec3(x: boxMax.x, y: boxMin.y, z: z), in: sceneSize),
            Tunnel.project(Vec3(x: boxMax.x, y: boxMax.y, z: z), in: sceneSize),
            Tunnel.project(Vec3(x: boxMin.x, y: boxMax.y, z: z), in: sceneSize),
        ]
    }

    private static func buildNode(boxMin: Vec3, boxMax: Vec3, color: SKColor, sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        let f = faceCorners(boxMin: boxMin, boxMax: boxMax, z: boxMin.z, sceneSize: sceneSize)
        let b = faceCorners(boxMin: boxMin, boxMax: boxMax, z: boxMax.z, sceneSize: sceneSize)

        // darker separating edges make each box pop against its neighbours
        let edgeColor = SKColor.black.withAlphaComponent(0.55)
        // everything far away is dimmer — applied to every face of this brick
        let depthDim = 0.42 + 0.58 * Tunnel.scale(at: boxMin.z)

        // generous rounding on every face so all 12 box edges read as soft:
        // front/back faces round the x/y edges; the side faces rounding into
        // the front and back faces softens the z edges as well
        let frontRadius = 13 * Tunnel.scale(at: boxMin.z)
        let backRadius = 13 * Tunnel.scale(at: boxMax.z)
        let sideRadius = (frontRadius + backRadius) / 2

        // faint back-face outline: the receding silhouette sells the volume
        node.addChild(quad(b, fill: shaded(color, 0.30 * depthDim),
                           stroke: SKColor.black.withAlphaComponent(0.4),
                           cornerRadius: backRadius))

        // sides facing the camera (toward the tunnel axis), lit as if from above:
        // top faces bright, bottom faces dark, left/right in between
        let cx = (boxMin.x + boxMax.x) / 2
        let cy = (boxMin.y + boxMax.y) / 2
        if cx > 1 { // brick is right of center: its left side is visible
            node.addChild(quad([f[0], f[3], b[3], b[0]], fill: shaded(color, 0.60 * depthDim),
                               stroke: edgeColor, cornerRadius: sideRadius))
        } else if cx < -1 { // right side visible
            node.addChild(quad([f[1], f[2], b[2], b[1]], fill: shaded(color, 0.60 * depthDim),
                               stroke: edgeColor, cornerRadius: sideRadius))
        }
        if cy > 1 { // brick above center: bottom side visible (in shadow)
            node.addChild(quad([f[0], f[1], b[1], b[0]], fill: shaded(color, 0.34 * depthDim),
                               stroke: edgeColor, cornerRadius: sideRadius))
        } else if cy < -1 { // top side visible (catches the light)
            node.addChild(quad([f[3], f[2], b[2], b[3]], fill: shaded(color, 1.05 * depthDim),
                               stroke: edgeColor, cornerRadius: sideRadius))
        }

        // front face on top: slightly deepened fill with a glowing neon rim —
        // the glow hugging the rounded corners is what sells the molded look
        let front = quad(f, fill: shaded(color, depthDim * 0.88),
                         stroke: shaded(color, 1.45).withAlphaComponent(0.9),
                         cornerRadius: frontRadius)
        front.lineWidth = 2
        front.glowWidth = 5 * Tunnel.scale(at: boxMin.z) * depthDim
        node.addChild(front)

        // specular strip along the top of the front face…
        let highlight = quad([f[3], f[2], lerp(f[2], f[1], 0.22), lerp(f[3], f[0], 0.22)],
                             fill: SKColor.white.withAlphaComponent(0.22 * depthDim),
                             stroke: .clear, cornerRadius: frontRadius)
        highlight.lineWidth = 0
        node.addChild(highlight)

        // …and an ambient-occlusion strip along the bottom, so the face reads
        // as a lit surface rather than flat color
        let shadowStrip = quad([f[0], f[1], lerp(f[1], f[2], 0.20), lerp(f[0], f[3], 0.20)],
                               fill: SKColor.black.withAlphaComponent(0.24),
                               stroke: .clear, cornerRadius: frontRadius)
        shadowStrip.lineWidth = 0
        node.addChild(shadowStrip)
        return node
    }
}
