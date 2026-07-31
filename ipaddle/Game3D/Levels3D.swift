import Foundation

/// 3D level maps: level → z-layers (front to rear) → rows (top to bottom).
/// Each row has 8 columns. Same brick alphabet as 2D:
/// '.' empty, '1' green (1 hit), '2' blue (2 hits), '3' red (3 hits), 'X' indestructible.
enum Levels3D {
    static let all: [[[String]]] = [
        // 1 — a single solid wall deep in the tunnel
        [
            [
                "11111111",
                "11111111",
                "12222221",
                "12222221",
                "11111111",
                "11111111",
            ],
        ],
        // 2 — armored donut
        [
            [
                "22222222",
                "2......2",
                "2.3333.2",
                "2.3333.2",
                "2......2",
                "22222222",
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
                ".1.1.1.1",
            ],
            [
                "22222222",
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
