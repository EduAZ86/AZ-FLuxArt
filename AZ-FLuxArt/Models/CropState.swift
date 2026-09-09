import CoreGraphics

struct CropState: Equatable {
    enum Mode: Equatable {
        case free
        case square
        case ratio(width: Double, height: Double)

        var label: String {
            switch self {
            case .free: return "Libre"
            case .square: return "1:1"
            case let .ratio(w, h): return "\(Int(w)):\(Int(h))"
            }
        }
    }

    var mode: Mode = .free
    var rect: CGRect? = nil
    var isActive: Bool = false

    static let none = CropState()

    var aspectRatio: CGFloat? {
        switch mode {
        case .free: return nil
        case .square: return 1
        case let .ratio(w, h): return w / h
        }
    }

    func pixelRect(imageSize: CGSize) -> CGRect {
        guard let rect else {
            return CGRect(origin: .zero, size: imageSize)
        }
        return CGRect(
            x: rect.minX * imageSize.width,
            y: rect.minY * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )
    }

    mutating func reset() {
        rect = nil
        mode = .free
    }
}