import CoreGraphics

/// Minimal 3D vector for the tunnel-mode physics.
struct Vec3 {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    static let zero = Vec3(x: 0, y: 0, z: 0)

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: Vec3, s: CGFloat) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }

    var length: CGFloat { sqrt(x * x + y * y + z * z) }

    func normalized() -> Vec3 {
        let len = length
        guard len > 0 else { return Vec3(x: 0, y: 0, z: 1) }
        return self * (1 / len)
    }
}

/// Tunnel geometry and the perspective projection.
///
/// World space: x/y centered on the tunnel axis (x right, y up), z = 0 at the
/// paddle plane (nearest the player) increasing into the screen. At z = 0 one
/// world unit equals one scene point, so the front cross-section maps 1:1.
enum Tunnel {
    static let width: CGFloat = 1000   // x ∈ [-500, 500] — nearly full screen
    static let height: CGFloat = 660   // y ∈ [-330, 330]
    static let depth: CGFloat = 1200   // z ∈ [0, 1200], rear wall at 1200
    static let focal: CGFloat = 640
    /// Tunnel axis sits slightly below scene center to leave room for the HUD.
    static let centerYOffset: CGFloat = -24

    static var halfW: CGFloat { width / 2 }
    static var halfH: CGFloat { height / 2 }

    static func scale(at z: CGFloat) -> CGFloat {
        focal / (focal + z)
    }

    static func project(_ p: Vec3, in sceneSize: CGSize) -> CGPoint {
        let s = scale(at: p.z)
        return CGPoint(x: sceneSize.width / 2 + p.x * s,
                       y: sceneSize.height / 2 + centerYOffset + p.y * s)
    }

    /// Projected corners of the tunnel cross-section rectangle at depth z.
    static func crossSection(at z: CGFloat, in sceneSize: CGSize) -> [CGPoint] {
        [
            project(Vec3(x: -halfW, y: -halfH, z: z), in: sceneSize),
            project(Vec3(x: halfW, y: -halfH, z: z), in: sceneSize),
            project(Vec3(x: halfW, y: halfH, z: z), in: sceneSize),
            project(Vec3(x: -halfW, y: halfH, z: z), in: sceneSize),
        ]
    }
}

enum Config3D {
    static let paddleSize = CGSize(width: 180, height: 130) // world units at z = 0
    static let paddleDepth: CGFloat = 34                    // z thickness of the paddle slab
    static let ballRadius: CGFloat = 13
    static let baseBallSpeed: CGFloat = 640
    static let speedPerLevel: CGFloat = 45
    static let maxBallSpeed: CGFloat = 980
    /// Minimum |vz| fraction so the ball never ping-pongs sideways forever.
    static let minDepthFraction: CGFloat = 0.32

    static let brickColumns = 8
    static let brickRows = 6
    static let brickThickness: CGFloat = 58  // z extent
    static let layerSpacing: CGFloat = 86    // front-to-front distance between z layers
    static let rearGap: CGFloat = 60         // space between rearmost layer and rear wall

    /// Ball is lost once it flies this far past the paddle plane.
    static let lossDepth: CGFloat = -170
}
