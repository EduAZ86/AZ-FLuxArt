import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case crop
    case adjust
    case effects
    case text
    case stickers
    case draw
    case erase
    case more

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crop: return "Recortar"
        case .adjust: return "Ajustar"
        case .effects: return "Efectos"
        case .text: return "Texto"
        case .stickers: return "Stickers"
        case .draw: return "Dibujar"
        case .erase: return "Borrador"
        case .more: return "Más"
        }
    }

    var systemImage: String {
        switch self {
        case .crop: return "crop"
        case .adjust: return "slider.horizontal.3"
        case .effects: return "wand.and.stars"
        case .text: return "textformat"
        case .stickers: return "face.smiling"
        case .draw: return "pencil.tip"
        case .erase: return "eraser"
        case .more: return "ellipsis"
        }
    }
}