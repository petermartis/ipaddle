import SpriteKit
import UIKit

/// A 3D brick: an axis-aligned box in tunnel space plus its pre-rendered
/// projected node. The front face is a single baked texture — rounded rect,
/// vertical light-to-dark gradient, soft inner highlight and a glowing neon
/// rim — so the shading is continuous (no layered strips). Side and back
/// faces are clean rounded polygons behind it. Multi-hit bricks accumulate
/// procedural cracks instead of changing color.
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
        let reach: CGFloat = stage == 1 ? 0.5 : 0.85

        let path = CGMutablePath()
        for i in 0..<branches {
            let edge = (i + Int.random(in: 0...1)) % 4
            let t = CGFloat.random(in: 0.2...0.8)
            let edgeTarget = Brick3D.lerp(f[edge], f[(edge + 1) % 4], t)
            let target = Brick3D.lerp(origin, edgeTarget, reach)
            path.move(to: origin)
            for step in 1...3 {
                var point = Brick3D.lerp(origin, target, CGFloat(step) / 3)
                if step < 3 {
                    point.x += CGFloat.random(in: -jitterScale...jitterScale)
                    point.y += CGFloat.random(in: -jitterScale...jitterScale)
                }
                path.addLine(to: point)
            }
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

    private static func quad(_ points: [CGPoint], fill: SKColor, cornerRadius: CGFloat) -> SKShapeNode {
        let shape = SKShapeNode(path: Draw.roundedPolygon(points, radius: cornerRadius))
        shape.fillColor = fill
        shape.strokeColor = .clear
        shape.lineWidth = 0
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

    // MARK: - Front-face texture baking

    private static var textureCache: [String: SKTexture] = [:]

    /// One smooth "gel button" texture: rounded rect, vertical gradient,
    /// soft top highlight, glowing rim. Cached per size/color/tone bucket.
    private static func frontTexture(color: SKColor, width: CGFloat, height: CGFloat,
                                     radius: CGFloat, tone: CGFloat) -> SKTexture {
        let key = String(format: "%.2f-%.2f-%.0fx%.0f-r%.0f-t%.2f",
                         colorKey(color).0, colorKey(color).1, width, height, radius, tone)
        if let cached = textureCache[key] { return cached }

        let base = shaded(color, tone)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let inset: CGFloat = 3 // room for the rim glow to breathe
            let rect = CGRect(x: inset, y: inset, width: width - 2 * inset, height: height - 2 * inset)
            let rounded = UIBezierPath(roundedRect: rect,
                                       cornerRadius: min(radius, min(rect.width, rect.height) / 2))
            let space = CGColorSpaceCreateDeviceRGB()

            // body: bright top rolling to a darker bottom (UIKit y-down)
            cg.saveGState()
            cg.addPath(rounded.cgPath)
            cg.clip()
            if let body = CGGradient(colorsSpace: space,
                                     colors: [shaded(base, 1.22).cgColor,
                                              shaded(base, 0.98).cgColor,
                                              shaded(base, 0.62).cgColor] as CFArray,
                                     locations: [0, 0.45, 1]) {
                cg.drawLinearGradient(body, start: CGPoint(x: 0, y: rect.minY),
                                      end: CGPoint(x: 0, y: rect.maxY), options: [])
            }
            // soft specular sheen across the top third
            if let sheen = CGGradient(colorsSpace: space,
                                      colors: [UIColor.white.withAlphaComponent(0.35).cgColor,
                                               UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                      locations: [0, 1]) {
                cg.drawLinearGradient(sheen, start: CGPoint(x: 0, y: rect.minY),
                                      end: CGPoint(x: 0, y: rect.minY + rect.height * 0.38),
                                      options: [])
            }
            cg.restoreGState()

            // glowing neon rim hugging the rounded outline
            let rim = shaded(base, 1.5)
            cg.setShadow(offset: .zero, blur: 5, color: rim.cgColor)
            cg.setStrokeColor(rim.withAlphaComponent(0.95).cgColor)
            cg.setLineWidth(2.5)
            cg.addPath(rounded.cgPath)
            cg.strokePath()
            cg.addPath(rounded.cgPath)
            cg.strokePath() // second pass strengthens the glow
        }
        let texture = SKTexture(image: image)
        textureCache[key] = texture
        return texture
    }

    private static func colorKey(_ color: SKColor) -> (CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r + b * 10, g)
    }

    private static func buildNode(boxMin: Vec3, boxMax: Vec3, color: SKColor, sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        let f = faceCorners(boxMin: boxMin, boxMax: boxMax, z: boxMin.z, sceneSize: sceneSize)
        let b = faceCorners(boxMin: boxMin, boxMax: boxMax, z: boxMax.z, sceneSize: sceneSize)
        let scaleF = Tunnel.scale(at: boxMin.z)

        // hand-made variance without touching the geometry: each brick gets
        // its own rounding amount and tone
        let wobble = CGFloat.random(in: 0.9...1.25)
        let tone = [0.94, 1.0, 1.06].randomElement()!
        let depthDim = 0.42 + 0.58 * scaleF

        // front face is an axis-aligned rect (constant z), so measure it
        let width = f[1].x - f[0].x
        let height = f[2].y - f[1].y
        let frontRadius = min(width, height) * 0.24 * wobble
        let backWidth = b[1].x - b[0].x
        let backHeight = b[2].y - b[1].y
        let backRadius = min(backWidth, backHeight) * 0.24 * wobble

        // back face silhouette
        node.addChild(quad(b, fill: shaded(color, 0.30 * depthDim), cornerRadius: backRadius))

        // sides facing the camera, lit from above — strokeless so they read
        // as the brick's own material turning away from the light
        let sideRadius = max(frontRadius, backRadius)
        let cx = (boxMin.x + boxMax.x) / 2
        let cy = (boxMin.y + boxMax.y) / 2
        if cx > 1 {
            node.addChild(quad([f[0], f[3], b[3], b[0]], fill: shaded(color, 0.55 * depthDim),
                               cornerRadius: sideRadius))
        } else if cx < -1 {
            node.addChild(quad([f[1], f[2], b[2], b[1]], fill: shaded(color, 0.55 * depthDim),
                               cornerRadius: sideRadius))
        }
        if cy > 1 {
            node.addChild(quad([f[0], f[1], b[1], b[0]], fill: shaded(color, 0.34 * depthDim),
                               cornerRadius: sideRadius))
        } else if cy < -1 {
            node.addChild(quad([f[3], f[2], b[2], b[3]], fill: shaded(color, 0.92 * depthDim),
                               cornerRadius: sideRadius))
        }

        // baked front face on top
        let texture = frontTexture(color: shaded(color, depthDim),
                                   width: max(width, 8), height: max(height, 8),
                                   radius: frontRadius, tone: tone)
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: width, height: height))
        sprite.position = CGPoint(x: (f[0].x + f[1].x) / 2, y: (f[1].y + f[2].y) / 2)
        sprite.zPosition = 2
        node.addChild(sprite)
        return node
    }
}
