import Foundation

enum PhysicsCategory {
    static let none: UInt32 = 0
    static let ball: UInt32 = 1 << 0
    static let paddle: UInt32 = 1 << 1
    static let brick: UInt32 = 1 << 2
    static let wall: UInt32 = 1 << 3
    static let bottom: UInt32 = 1 << 4
    static let powerUp: UInt32 = 1 << 5
    static let laser: UInt32 = 1 << 6
}
