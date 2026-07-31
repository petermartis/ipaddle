import SpriteKit

/// A 3D brick: an axis-aligned box in tunnel space plus its pre-rendered
/// projected node (front face, back face, and the sides that face the camera).
final class Brick3D {
    let boxMin: Vec3
    let boxMax: Vec3
    let pointValue: Int
    let isIndestructible: Bool
    let node: SKNode
    private(set) var hitPoints: Int
    private(set) var isAlive = true

    var center: Vec3 {
        Vec3(x: (boxMin.x + boxMax.x) / 2,
             y: (boxMin.y + boxMax.y) / 2,
             z: (boxMin.z + boxMax.z) / 2)
    }
    let color: SKColor

    private static func style(for char: Character) -> (hp: Int, points: Int, color: SKColor, indestructible: Bool)? {
        switch char {
        case "1": return (1, 50, SKColor(red: 0.37, green: 0.75, blue: 0.35, alpha: 1), false)
        case "2": return (2, 100, SKColor(red: 0.28, green: 0.55, blue: 0.92, alpha: 1), false)
        case "3": return (3, 150, SKColor(red: 0.89, green: 0.24, blue: 0.24, alpha: 1), false)
        case "X": return (0, 0, SKColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1), true)
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
        node.alpha = 0.45 + 0.55 * CGFloat(hitPoints) / 3.0
        node.run(SKAction.sequence([
            SKAction.fadeAlpha(to: node.alpha * 0.5, duration: 0.05),
            SKAction.fadeAlpha(to: node.alpha, duration: 0.05),
        ]))
        return false
    }

    // MARK: - Rendering

    private static func shaded(_ color: SKColor, _ factor: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
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

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func buildNode(boxMin: Vec3, boxMax: Vec3, color: SKColor, sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        func corner(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            Tunnel.project(Vec3(x: x, y: y, z: z), in: sceneSize)
        }
        // front face corners (z = boxMin.z): 0 bottom-left, 1 bottom-right, 2 top-right, 3 top-left
        let f = [corner(boxMin.x, boxMin.y, boxMin.z), corner(boxMax.x, boxMin.y, boxMin.z),
                 corner(boxMax.x, boxMax.y, boxMin.z), corner(boxMin.x, boxMax.y, boxMin.z)]
        // back face corners (z = boxMax.z)
        let b = [corner(boxMin.x, boxMin.y, boxMax.z), corner(boxMax.x, boxMin.y, boxMax.z),
                 corner(boxMax.x, boxMax.y, boxMax.z), corner(boxMin.x, boxMax.y, boxMax.z)]

        // darker separating edges make each box pop against its neighbours
        let edgeColor = SKColor.black.withAlphaComponent(0.55)
        // everything far away is dimmer — applied to every face of this brick
        let depthDim = 0.42 + 0.58 * Tunnel.scale(at: boxMin.z)

        // corner rounding shrinks with perspective like everything else
        let frontRadius = 7 * Tunnel.scale(at: boxMin.z)
        let backRadius = 7 * Tunnel.scale(at: boxMax.z)

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
                               stroke: edgeColor, cornerRadius: backRadius))
        } else if cx < -1 { // right side visible
            node.addChild(quad([f[1], f[2], b[2], b[1]], fill: shaded(color, 0.60 * depthDim),
                               stroke: edgeColor, cornerRadius: backRadius))
        }
        if cy > 1 { // brick above center: bottom side visible (in shadow)
            node.addChild(quad([f[0], f[1], b[1], b[0]], fill: shaded(color, 0.34 * depthDim),
                               stroke: edgeColor, cornerRadius: backRadius))
        } else if cy < -1 { // top side visible (catches the light)
            node.addChild(quad([f[3], f[2], b[2], b[3]], fill: shaded(color, 1.05 * depthDim),
                               stroke: edgeColor, cornerRadius: backRadius))
        }

        // front face on top
        let front = quad(f, fill: shaded(color, depthDim), stroke: edgeColor,
                         cornerRadius: frontRadius)
        front.lineWidth = 1.5
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
