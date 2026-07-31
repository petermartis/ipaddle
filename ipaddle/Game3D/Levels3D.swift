import Foundation

/// 3D level maps: level → z-layers (front to rear) → rows (top to bottom).
/// Grid size comes from the map itself: early levels use few columns/rows,
/// so their bricks are huge; later levels shrink the bricks (and the ball
/// speeds up per level on top of that).
/// Brick alphabet: '.' empty, '1' green (1 hit), '2' blue (2 hits),
/// '3' red (3 hits), 'X' indestructible.
enum Levels3D {
    static let all: [[[String]]] = [
        // 1 — four-by-three wall of giant bricks
        [
            [
                "1111",
                "1221",
                "1111",
            ],
        ],
        // 2 — six-by-four armored donut
        [
            [
                "222222",
                "2.33.2",
                "2.33.2",
                "222222",
            ],
        ],
        // 3 — two layers: checkerboard screen in front of a solid wall
        [
            [
                "1.1.1.1.",
                ".1.1.1.1",
                "1.1.1.1.",
                ".1.1.1.1",
                "1.1.1.1.",
            ],
            [
                "22222222",
                "22222222",
                "22222222",
                "22222222",
                "22222222",
            ],
        ],
        // 4 — floating core guarded by an armored frame
        [
            [
                "........",
                "..3333..",
                ".322223.",
                ".322223.",
                "..3333..",
                "........",
            ],
            [
                "XX2222XX",
                "X2....2X",
                "2..11..2",
                "2..11..2",
                "X2....2X",
                "XX2222XX",
            ],
        ],
    ]
}
