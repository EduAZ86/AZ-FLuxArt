import SwiftUI
import CoreGraphics
import AppKit

// MARK: - StickerInfo (NSCoding)

final class StickerInfo: NSCoding {
    var name: String
    var pngData: Data?
    var dateCreated: Date

    init(name: String, pngData: Data? = nil, dateCreated: Date = Date()) {
        self.name = name
        self.pngData = pngData
        self.dateCreated = dateCreated
    }

    func encode(with coder: NSCoder) {
        coder.encode(name, forKey: "name")
        coder.encode(pngData, forKey: "pngData")
        coder.encode(dateCreated, forKey: "dateCreated")
    }

    required convenience init?(coder: NSCoder) {
        let name = coder.decodeObject(forKey: "name") as? String ?? ""
        let pngData = coder.decodeObject(forKey: "pngData") as? Data
        let dateCreated = coder.decodeObject(forKey: "dateCreated") as? Date ?? Date()
        self.init(name: name, pngData: pngData, dateCreated: dateCreated)
    }
}

// MARK: - TextLayerContent (NSCoding)

final class TextLayerContent: NSCoding {
    var text: String
    var fontSize: CGFloat
    var colorRGB: String  // "r,g,b" 0-255

    init(text: String, fontSize: CGFloat = 64, colorRGB: String = "0,0,0") {
        self.text = text
        self.fontSize = fontSize
        self.colorRGB = colorRGB
    }

    init(text: String, fontSize: CGFloat = 64, color: Color = .black) {
        self.text = text
        self.fontSize = fontSize
        let ns = NSColor(color)
        let r = Int(ns.redComponent * 255)
        let g = Int(ns.greenComponent * 255)
        let b = Int(ns.blueComponent * 255)
        self.colorRGB = "\(r),\(g),\(b)"
    }

    var color: Color {
        let comps = colorRGB.split(separator: ",").compactMap { Double($0) }
        if comps.count == 3 {
            return Color(red: comps[0]/255, green: comps[1]/255, blue: comps[2]/255)
        }
        return .black
    }

    func encode(with coder: NSCoder) {
        coder.encode(text, forKey: "text")
        coder.encode(fontSize, forKey: "fontSize")
        coder.encode(colorRGB, forKey: "colorRGB")
    }

    required convenience init?(coder: NSCoder) {
        let text = coder.decodeObject(forKey: "text") as? String ?? ""
        let fontSize = coder.decodeObject(forKey: "fontSize") as? CGFloat ?? 64
        let colorRGB = coder.decodeObject(forKey: "colorRGB") as? String ?? "0,0,0"
        self.init(text: text, fontSize: fontSize, colorRGB: colorRGB)
    }

    static let defaultFontSize: CGFloat = 64
}

// MARK: - LayerTransform (Codable para archiving)

struct LayerTransform: Codable, Equatable {
    var center: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var scale: CGFloat = 1
    var rotation: CGFloat = 0

    static let identity = LayerTransform()
}

// MARK: - LayerContent (NSCoding)

final class LayerContent: NSCoding {
    enum Kind: String {
        case image, text, stickerUser, sticker
    }

    var kind: Kind
    var nsImage: NSImage?
    var textContent: TextLayerContent?
    var stickerInfo: StickerInfo?
    var stickerEmoji: String?

    // Inits
    init(image: CGImage) {
        self.kind = .image
        let ns = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        self.nsImage = ns
    }

    init(nsImage: NSImage) {
        self.kind = .image
        self.nsImage = nsImage
    }

    init(text: TextLayerContent) {
        self.kind = .text
        self.textContent = text
    }

    init(stickerUser: StickerInfo) {
        self.kind = .stickerUser
        self.stickerInfo = stickerUser
    }

    init(stickerEmoji: String) {
        self.kind = .sticker
        self.stickerEmoji = stickerEmoji
    }

    func encode(with coder: NSCoder) {
        coder.encode(kind.rawValue, forKey: "kind")
        switch kind {
        case .image: coder.encode(nsImage, forKey: "nsImage")
        case .text: coder.encode(textContent, forKey: "textContent")
        case .stickerUser: coder.encode(stickerInfo, forKey: "stickerInfo")
        case .sticker: coder.encode(stickerEmoji, forKey: "stickerEmoji")
        }
    }

    required convenience init?(coder: NSCoder) {
        let kindStr = coder.decodeObject(forKey: "kind") as? String ?? "image"
        let kind = Kind(rawValue: kindStr) ?? .image
        self.init(kind: kind)
        switch kind {
        case .image: nsImage = coder.decodeObject(forKey: "nsImage") as? NSImage
        case .text: textContent = coder.decodeObject(forKey: "textContent") as? TextLayerContent
        case .stickerUser: stickerInfo = coder.decodeObject(forKey: "stickerInfo") as? StickerInfo
        case .sticker: stickerEmoji = coder.decodeObject(forKey: "stickerEmoji") as? String
        }
    }

    private init(kind: Kind) {
        self.kind = kind
    }

    @MainActor
func cgImage() -> CGImage? {
        switch kind {
        case .image:
            guard let ns = nsImage else { return nil }
            var rect = NSRect(origin: .zero, size: ns.size)
            return ns.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        case .text:
            guard let t = textContent else { return nil }
            return Renderer.renderTextToCGImage(t)
        case .stickerUser:
            guard let info = stickerInfo,
                  let data = info.pngData,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        case .sticker:
            guard let emoji = stickerEmoji else { return nil }
            return Renderer.renderStickerToCGImage(emoji)
        }
    }
}

// MARK: - Layer (NSCoding)

final class Layer: Identifiable, ObservableObject, NSCoding {
    let id = UUID()
    var name: String
    var content: LayerContent

    @Published var isVisible: Bool = true
    @Published var opacity: Double = 1.0
    @Published var isLocked: Bool = false
    @Published var transform = LayerTransform()

    init(name: String, content: LayerContent) {
        self.name = name
        self.content = content
    }

    func encode(with coder: NSCoder) {
        coder.encode(name, forKey: "name")
        coder.encode(content, forKey: "content")
        coder.encode(isVisible, forKey: "isVisible")
        coder.encode(opacity, forKey: "opacity")
        coder.encode(isLocked, forKey: "isLocked")
        let data = try? JSONEncoder().encode(transform)
        coder.encode(data, forKey: "transform")
    }

    required convenience init?(coder: NSCoder) {
        let name = coder.decodeObject(forKey: "name") as? String ?? "Layer"
        let content = coder.decodeObject(forKey: "content") as? LayerContent ?? LayerContent(nsImage: NSImage())
        self.init(name: name, content: content)
        isVisible = coder.decodeBool(forKey: "isVisible")
        opacity = coder.decodeDouble(forKey: "opacity")
        isLocked = coder.decodeBool(forKey: "isLocked")
        if let data = coder.decodeObject(forKey: "transform") as? Data,
           let t = try? JSONDecoder().decode(LayerTransform.self, from: data) {
            transform = t
        } else {
            transform = .identity
        }
    }

    func snapshotCopy() -> Layer {
        let copy = Layer(name: name, content: content)
        copy.isVisible = isVisible
        copy.opacity = opacity
        copy.isLocked = isLocked
        copy.transform = transform
        return copy
    }
}