import SwiftUI

enum EffectPreset: String, CaseIterable, Identifiable {
    case none
    case mono
    case sepia
    case noir
    case vignette
    case bloom
    case pixellate
    case gloom
    case comic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Ninguno"
        case .mono: return "Mono"
        case .sepia: return "Sepia"
        case .noir: return "Noir"
        case .vignette: return "Viñeta"
        case .bloom: return "Bloom"
        case .pixellate: return "Pixelado"
        case .gloom: return "Gloom"
        case .comic: return "Cómic"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "xmark.circle"
        case .mono: return "circle.lefthalf.filled"
        case .sepia: return "circle.righthalf.filled"
        case .noir: return "moon.fill"
        case .vignette: return "circle.circle"
        case .bloom: return "sun.max.fill"
        case .pixellate: return "square.grid.3x3"
        case .gloom: return "cloud.fill"
        case .comic: return "paintbrush.pointed.fill"
        }
    }
}

enum BrushStroke: Equatable {
    case stroke(Stroke)

    static func == (lhs: BrushStroke, rhs: BrushStroke) -> Bool {
        switch (lhs, rhs) {
        case let (.stroke(a), .stroke(b)): return a == b
        }
    }
}

struct Stroke: Equatable {
    var points: [CGPoint]
    var color: Color
    var width: CGFloat
    var isEraser: Bool
}