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

    private static func quad(_ points: [CGPoint], fill: SKColor, stroke: SKColor) -> SKShapeNode {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = fill
        shape.strokeColor = stroke
        shape.lineWidth = 1
        shape.lineJoin = .miter
        return shape
    }

    private static func buildNode(boxMin: Vec3, boxMax: Vec3, color: SKColor, sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        func corner(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            Tunnel.project(Vec3(x: x, y: y, z: z), in: sceneSize)
        }
        // front face corners (z = boxMin.z), counter-clockwise from bottom-left
        let f = [corner(boxMin.x, boxMin.y, boxMin.z), corner(boxMax.x, boxMin.y, boxMin.z),
                 corner(boxMax.x, boxMax.y, boxMin.z), corner(boxMin.x, boxMax.y, boxMin.z)]
        // back face corners (z = boxMax.z)
        let b = [corner(boxMin.x, boxMin.y, boxMax.z), corner(boxMax.x, boxMin.y, boxMax.z),
                 corner(boxMax.x, boxMax.y, boxMax.z), corner(boxMin.x, boxMax.y, boxMax.z)]

        let edgeColor = SKColor.white.withAlphaComponent(0.22)

        // sides facing the camera (toward the tunnel axis), drawn before the front face
        let cx = (boxMin.x + boxMax.x) / 2
        let cy = (boxMin.y + boxMax.y) / 2
        if cx > 1 { // brick is right of center: its left side is visible
            node.addChild(quad([f[0], f[3], b[3], b[0]], fill: shaded(color, 0.55), stroke: edgeColor))
        } else if cx < -1 { // right side visible
            node.addChild(quad([f[1], f[2], b[2], b[1]], fill: shaded(color, 0.55), stroke: edgeColor))
        }
        if cy > 1 { // brick above center: bottom side visible
            node.addChild(quad([f[0], f[1], b[1], b[0]], fill: shaded(color, 0.42), stroke: edgeColor))
        } else if cy < -1 { // top side visible
            node.addChild(quad([f[3], f[2], b[2], b[3]], fill: shaded(color, 0.72), stroke: edgeColor))
        }

        // front face on top, dimmed slightly with depth so far layers read as farther
        let depthDim = 0.55 + 0.45 * Tunnel.scale(at: boxMin.z)
        node.addChild(quad(f, fill: shaded(color, depthDim), stroke: SKColor.white.withAlphaComponent(0.3)))
        return node
    }
}
