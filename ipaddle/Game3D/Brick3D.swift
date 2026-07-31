import SpriteKit
import UIKit

/// A 3D brick: an axis-aligned box in tunnel space, rendered as a single
/// baked sprite with pillow-soft volumetric shading — edge roll-off on all
/// four sides, a corner specular, a baked drop shadow, and a subtle neon
/// glow. No assembled face panels: the softness of one continuous surface
/// is what makes it read as a molded solid.
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

    // MARK: - Baked brick body

    private static var textureCache: [String: SKTexture] = [:]
    /// Canvas padding around the body for glow and drop shadow.
    static let texturePadding: CGFloat = 22

    /// The whole brick as one soft-shaded extruded body:
    /// drop shadow → swept extrusion toward the vanishing point → pillow
    /// face with edge roll-off → top light → corner specular → neon rim.
    /// (extrusionX/Y is the screen-space offset of the brick's back face,
    /// pointing at the tunnel's vanishing point; zero for center bricks.)
    private static func brickTexture(color: SKColor, width: CGFloat, height: CGFloat,
                                     radius: CGFloat, tone: CGFloat,
                                     extrusionX: CGFloat, extrusionY: CGFloat) -> SKTexture {
        var r: CGFloat = 0, g: CGFloat = 0, b2: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b2, alpha: &a)
        let key = String(format: "brick-%.2f-%.2f-%.2f-%.0fx%.0f-r%.0f-t%.2f-e%.0f,%.0f",
                         r, g, b2, width, height, radius, tone, extrusionX, extrusionY)
        if let cached = textureCache[key] { return cached }

        let base = shaded(color, tone)
        let pad = texturePadding
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let canvas = CGSize(width: width + pad * 2, height: height + pad * 2)
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: pad, y: pad, width: width, height: height)
            let corner = min(radius, min(width, height) / 2)
            let rounded = UIBezierPath(roundedRect: rect, cornerRadius: corner)
            let space = CGColorSpaceCreateDeviceRGB()

            // scene y-up → UIKit y-down for the extrusion direction
            let ex = extrusionX
            let ey = -extrusionY

            // 1. drop shadow under the whole body (front + extruded back)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 7), blur: 12,
                         color: UIColor.black.withAlphaComponent(0.55).cgColor)
            cg.setFillColor(base.cgColor)
            cg.addPath(rounded.cgPath)
            cg.fillPath()
            cg.restoreGState()

            // 2. swept extrusion: the body recedes toward the vanishing
            // point in many small steps, darkening as it goes — a smooth
            // molded flank rather than a hard side panel
            if abs(ex) > 0.5 || abs(ey) > 0.5 {
                let steps = 16
                for i in stride(from: steps, through: 1, by: -1) {
                    let t = CGFloat(i) / CGFloat(steps) // 1 = deepest
                    let stepRect = rect
                        .offsetBy(dx: ex * t, dy: ey * t)
                        .insetBy(dx: 1.5 * t, dy: 1.5 * t)
                    let stepPath = UIBezierPath(roundedRect: stepRect,
                                                cornerRadius: max(2, corner - 1.5 * t))
                    cg.setFillColor(shaded(base, 0.30 + 0.35 * (1 - t)).cgColor)
                    cg.addPath(stepPath.cgPath)
                    cg.fillPath()
                }
            }

            // 2. pillow roll-off: an inner shadow bleeding in from every
            // edge, following the rounded contour — this is what makes the
            // surface look curved in all directions
            cg.saveGState()
            cg.addPath(rounded.cgPath)
            cg.clip()
            cg.setShadow(offset: .zero, blur: min(width, height) * 0.22,
                         color: UIColor.black.withAlphaComponent(0.65).cgColor)
            let inverse = CGMutablePath()
            inverse.addRect(CGRect(x: -60, y: -60, width: canvas.width + 120, height: canvas.height + 120))
            inverse.addPath(rounded.cgPath)
            cg.addPath(inverse)
            cg.setFillColor(UIColor.black.cgColor)
            cg.fillPath(using: .evenOdd)

            // 3. light from above: gentle brightening of the top half
            if let light = CGGradient(colorsSpace: space,
                                      colors: [UIColor.white.withAlphaComponent(0.30).cgColor,
                                               UIColor.white.withAlphaComponent(0).cgColor,
                                               UIColor.black.withAlphaComponent(0.18).cgColor] as CFArray,
                                      locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(light, start: CGPoint(x: 0, y: rect.minY),
                                      end: CGPoint(x: 0, y: rect.maxY), options: [])
            }

            // 4. corner specular glint (as on the reference cube)
            if let glint = CGGradient(colorsSpace: space,
                                      colors: [UIColor.white.withAlphaComponent(0.55).cgColor,
                                               UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                      locations: [0, 1]) {
                let center = CGPoint(x: rect.minX + rect.width * 0.26,
                                     y: rect.minY + rect.height * 0.24)
                cg.drawRadialGradient(glint, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: min(width, height) * 0.55,
                                      options: [])
            }
            cg.restoreGState()

            // 5. faint neon rim so the palette still glows, without a hard
            // sticker outline
            cg.setShadow(offset: .zero, blur: 7,
                         color: shaded(base, 1.5).cgColor)
            cg.setStrokeColor(shaded(base, 1.45).withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(1.5)
            cg.addPath(rounded.cgPath)
            cg.strokePath()
        }
        let texture = SKTexture(image: image)
        textureCache[key] = texture
        return texture
    }

    private static func buildNode(boxMin: Vec3, boxMax: Vec3, color: SKColor, sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        let f = faceCorners(boxMin: boxMin, boxMax: boxMax, z: boxMin.z, sceneSize: sceneSize)
        let scaleF = Tunnel.scale(at: boxMin.z)

        // hand-made variance: each brick gets its own rounding and tone
        let wobble = CGFloat.random(in: 0.9...1.25)
        let tone = [0.94, 1.0, 1.06].randomElement()!
        let depthDim = 0.42 + 0.58 * scaleF

        // front face is an axis-aligned rect (constant z), so measure it
        let width = f[1].x - f[0].x
        let height = f[2].y - f[1].y
        let radius = min(width, height) * 0.26 * wobble

        // extrusion direction: toward the tunnel's vanishing point, growing
        // with distance from the axis (center bricks show no flank, just as
        // a real head-on box would)
        let frontCenter = CGPoint(x: (f[0].x + f[1].x) / 2, y: (f[1].y + f[2].y) / 2)
        let vanishing = CGPoint(x: sceneSize.width / 2,
                                y: sceneSize.height / 2 + Tunnel.centerYOffset)
        let dx = vanishing.x - frontCenter.x
        let dy = vanishing.y - frontCenter.y
        let dist = max(hypot(dx, dy), 0.001)
        let flankLength = min(16, min(width, height) * 0.16) * min(1, dist / 260)
        let ex = (dx / dist * flankLength).rounded()
        let ey = (dy / dist * flankLength).rounded()

        let texture = brickTexture(color: shaded(color, depthDim),
                                   width: max(width, 8), height: max(height, 8),
                                   radius: radius, tone: tone,
                                   extrusionX: ex, extrusionY: ey)
        let pad = Brick3D.texturePadding
        let sprite = SKSpriteNode(texture: texture,
                                  size: CGSize(width: width + pad * 2, height: height + pad * 2))
        sprite.position = CGPoint(x: (f[0].x + f[1].x) / 2, y: (f[1].y + f[2].y) / 2)
        node.addChild(sprite)
        return node
    }
}
