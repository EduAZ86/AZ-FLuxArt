import SwiftUI
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension CGImage {
    var pngData: Data? {
        let nsImage = NSImage(cgImage: self, size: NSSize(width: width, height: height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
final class EditorViewModel: NSObject, ObservableObject, NSCoding {
    // Estado del documento
    @Published var layers: [Layer] = []
    @Published var activeLayerID: UUID?
    @Published var adjustments = Adjustments()
    @Published var crop = CropState()
    @Published var effect: EffectPreset = .none
    @Published var effectIntensity: Double = 0.8

    // UI
    @Published var activeTool: EditorTool?
    @Published var showLayersPanel = false
    @Published var editorTitle = "Nuevo proyecto"

    // IA
    @Published var aiModelInstalled = false
    @Published var isDownloadingAIModel = false

    // Dibujo / borrador (trazo en curso, aún no rasterizado)
    @Published var strokes: [Stroke] = []
    @Published var currentStrokePoints: [CGPoint] = []
    @Published var brushColor: Color = .black
    @Published var brushWidth: Double = 12
    @Published var isErasing = false

    @Published private(set) var renderedImage: CGImage?

    // Estado de edición de sticker
    private var editingStickerID: UUID?

    // Estado de apertura de tool (para Cancelar)
    private var openingAdjustments = Adjustments()
    private var openingCrop = CropState()
    private var openingEffect: EffectPreset = .none

    // Undo / redo
    private struct Snapshot {
        let layers: [Layer]
        let adjustments: Adjustments
        let crop: CropState
        let effect: EffectPreset
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private static let undoLimit = 40
    @Published var canUndo = false
    @Published var canRedo = false

    // MARK: - Importar

    func importImage(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        addImageLayer(cg, name: url.lastPathComponent)
    }

    @discardableResult
    func addImageLayer(_ cg: CGImage, name: String) -> Layer {
        let layer = Layer(name: name, content: LayerContent(image: cg))
        layers.append(layer)
        activeLayerID = layer.id
        editorTitle = name
        pushSnapshot()
        render()
        return layer
    }

    func addTextLayer(_ content: TextLayerContent) {
        let layer = Layer(name: "Texto", content: LayerContent(text: content))
        layers.append(layer)
        activeLayerID = layer.id
        pushSnapshot()
        render()
    }

    func addStickerLayer(_ emoji: String) {
        let layer = Layer(name: "Sticker", content: LayerContent(stickerEmoji: emoji))
        layers.append(layer)
        activeLayerID = layer.id
        pushSnapshot()
        render()
    }

    // MARK: - Biblioteca de stickers (stickerUser)

    /// Todos los stickers creados por el usuario (capas .stickerUser)
    var stickers: [Layer] {
        layers.filter { $0.content.kind == .stickerUser }
    }

    /// Agrega un sticker de la biblioteca al canvas actual
    func useStickerFromLibrary(_ stickerLayer: Layer) {
        guard let cg = stickerLayer.content.cgImage() else { return }
        let copy = Layer(name: stickerLayer.name, content: LayerContent(image: cg))
        copy.opacity = stickerLayer.opacity
        copy.transform = stickerLayer.transform
        layers.append(copy)
        activeLayerID = copy.id
        pushSnapshot()
        render()
    }

    /// Elimina un sticker de la biblioteca
    func removeStickerFromLibrary(_ stickerLayer: Layer) {
        layers.removeAll { $0.id == stickerLayer.id }
        pushSnapshot()
        render()
    }

    /// Renombra un sticker de la biblioteca
    func renameSticker(_ stickerLayer: Layer, to newName: String) {
        stickerLayer.name = newName
        pushSnapshot()
    }

    /// Edita un sticker: abre el recorte con su imagen actual
    func editSticker(_ stickerLayer: Layer) {
        guard let cg = stickerLayer.content.cgImage() else { return }
        // Reemplaza la capa original con su imagen base para recortar de nuevo
        stickerLayer.content = LayerContent(image: cg)
        stickerLayer.transform = .identity
        crop.rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        crop.isActive = true
        activeTool = .crop
        // Guardar referencia para saber que estamos editando este sticker
        editingStickerID = stickerLayer.id
        render()
    }

    /// Finaliza la edición del sticker (llamado al aplicar recorte)
    func finishStickerEdit(name: String?) {
        guard let id = editingStickerID,
              let idx = layers.firstIndex(where: { $0.id == id }) else {
            editingStickerID = nil
            return
        }
        if let n = name, !n.isEmpty {
            layers[idx].name = n
        }
        // El recorte ya se aplicó en bakeCrop, y la capa quedó como .image
        // La convertimos a stickerUser
        let layer = layers[idx]
        if let cg = layer.content.cgImage() {
            let pngData = cg.pngData
            let info = StickerInfo(name: layer.name, pngData: pngData, dateCreated: Date())
            layer.content = LayerContent(stickerUser: info)
        }
        editingStickerID = nil
        pushSnapshot()
        render()
    }

    // MARK: - Capas

    var activeLayer: Layer? {
        layers.first { $0.id == activeLayerID }
    }

    func duplicateActiveLayer() {
        guard let active = activeLayer else { return }
        guard let cg = Renderer.cgImage(for: active.content) else { return }
        let copy = Layer(name: active.name, content: LayerContent(image: cg))
        copy.opacity = active.opacity
        copy.isVisible = active.isVisible
        if let idx = layers.firstIndex(where: { $0.id == active.id }) {
            layers.insert(copy, at: idx + 1)
        } else {
            layers.append(copy)
        }
        activeLayerID = copy.id
        pushSnapshot()
        render()
    }

    func deleteActiveLayer() {
        guard activeLayerID != nil else { return }
        layers.removeAll { $0.id == activeLayerID }
        activeLayerID = layers.last?.id
        pushSnapshot()
        render()
    }

    func deleteLayer(_ layer: Layer) {
        layers.removeAll { $0.id == layer.id }
        if activeLayerID == layer.id {
            activeLayerID = layers.last?.id
        }
        pushSnapshot()
        render()
    }

    func moveLayer(_ layer: Layer, by offset: Int) {
        guard let from = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        let to = from + offset
        guard to >= 0, to < layers.count else { return }
        layers.move(fromOffsets: IndexSet(integer: from), toOffset: to + (offset > 0 ? 1 : 0))
        pushSnapshot()
        render()
    }

    func toggleLayerVisibility(_ layer: Layer) {
        layer.isVisible.toggle()
        render()
    }

    func setLayerOpacity(_ layer: Layer, _ value: Double) {
        layer.opacity = value
        render()
    }

    func deselectLayer() {
        activeLayerID = nil
    }

    // MARK: - Transformación no destructiva

    private var layerNaturalSizes: [UUID: CGSize] = [:]

    /// Tamaño natural (en píxeles) del contenido de la capa, cacheado por id.
    func naturalPixelSize(for layer: Layer) -> CGSize {
        if let cached = layerNaturalSizes[layer.id] { return cached }
        guard let cg = Renderer.cgImage(for: layer.content) else { return .zero }
        let size = CGSize(width: cg.width, height: cg.height)
        layerNaturalSizes[layer.id] = size
        return size
    }

    /// Actualiza en vivo el transform de la capa activa (durante el arrastre).
    func updateActiveLayerTransform(_ transform: LayerTransform) {
        activeLayer?.transform = transform
        render()
    }

    /// Confirma la transformación (para undo).
    func commitActiveLayerTransform() {
        pushSnapshot()
    }

    func resetActiveLayerTransform() {
        guard let active = activeLayer else { return }
        active.transform = .identity
        pushSnapshot()
        render()
    }

    // MARK: - Transformaciones rápidas (panel "Más")

    func flipActiveLayer(horizontal: Bool) {
        guard let active = activeLayer,
              let cg = Renderer.cgImage(for: active.content),
              let transformed = Renderer.transformImage(cg, flipHorizontal: horizontal, flipVertical: !horizontal, rotateDegrees: 0) else { return }
        active.content = LayerContent(image: transformed)
        pushSnapshot()
        render()
    }

    func rotateActiveLayer(degrees: Int) {
        guard let active = activeLayer,
              let cg = Renderer.cgImage(for: active.content),
              let transformed = Renderer.transformImage(cg, flipHorizontal: false, flipVertical: false, rotateDegrees: degrees) else { return }
        active.content = LayerContent(image: transformed)
        pushSnapshot()
        render()
    }

    // MARK: - Tools

    func selectTool(_ tool: EditorTool) {
        guard activeTool != tool else { return }
        openingAdjustments = adjustments
        openingCrop = crop
        openingEffect = effect

        if tool == .crop {
            crop.isActive = true
        }
        if tool == .draw || tool == .erase {
            strokes.removeAll()
            currentStrokePoints.removeAll()
        }
        activeTool = tool
        render()
    }

    func cancelTool() {
        adjustments = openingAdjustments
        crop = openingCrop
        effect = openingEffect
        strokes.removeAll()
        currentStrokePoints.removeAll()
        activeTool = nil
        render()
    }

    func applyTool() {
        switch activeTool {
        case .crop:
            if editingStickerID != nil {
                finishStickerEdit(name: nil)
            } else {
                bakeCrop()
            }
        case .draw:
            commitDraw()
        case .erase:
            commitErase()
        default:
            break
        }
        strokes.removeAll()
        currentStrokePoints.removeAll()
        pushSnapshot()
        activeTool = nil
        render()
    }

    func dismissTool() {
        activeTool = nil
    }

    // MARK: - IA

    /// Descarga e instala el modelo local de IA. Por ahora es un stub de UI:
    /// aquí se conectará la descarga real del modelo cuando esté disponible.
    func downloadAIModel() {
        guard !aiModelInstalled, !isDownloadingAIModel else { return }
        isDownloadingAIModel = true
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                aiModelInstalled = true
            } catch {}
            isDownloadingAIModel = false
        }
    }

    // MARK: - Recorte

    /// Aplica físicamente el recorte sobre la primera capa de imagen (estilo Picsart):
    /// el resto de herramientas operan sobre la imagen ya recortada.
    private func bakeCrop() {
        defer {
            crop.isActive = false
            crop.rect = nil
        }
        guard let rect = crop.rect, rect.width > 0.001, rect.height > 0.001,
              let idx = layers.firstIndex(where: {
                  if case .image = $0.content.kind { return true }
                  return false
              }),
              let base = layers[idx].content.cgImage() else { return }

        let size = canvasPixelSize
        let pixel = crop.pixelRect(imageSize: size).integral
        let clipped = CGRect(x: 0, y: 0, width: size.width, height: size.height).intersection(pixel)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return }

        // Componer la base con su transform: se recorta "lo que se ve".
        let composited = Renderer.compositedLayer(base, transform: layers[idx].transform, canvasSize: size)
        let source = composited ?? base
        guard let cropped = source.cropping(to: clipped) else { return }
        layers[idx].content = LayerContent(image: cropped)
        layers[idx].transform = .identity

        // Re-anclar las demás capas visibles al nuevo lienzo (crop estilo Picsart).
        let oldSize = size
        let newSize = CGSize(width: clipped.width, height: clipped.height)
        let co = CGPoint(x: clipped.minX / oldSize.width, y: clipped.minY / oldSize.height)
        let cn = CGSize(width: clipped.width / oldSize.width, height: clipped.height / oldSize.height)
        let areaK = sqrt((oldSize.width * oldSize.height) / (newSize.width * newSize.height))
        for (i, layer) in layers.enumerated() where i != idx && layer.isVisible {
            var t = layer.transform
            if cn.width > 0.001 && cn.height > 0.001 {
                t.center = CGPoint(
                    x: min(1, max(0, (t.center.x - co.x) / cn.width)),
                    y: min(1, max(0, (t.center.y - co.y) / cn.height))
                )
            }
            t.scale = t.scale * areaK
            layer.transform = t
        }
    }

    // MARK: - Dibujo / borrador

    func beginStroke(at point: CGPoint, isEraser: Bool) {
        isErasing = isEraser
        currentStrokePoints = [point]
    }

    func appendStrokePoint(_ point: CGPoint) {
        currentStrokePoints.append(point)
        if let last = strokes.last, currentStrokePoints.count > 1 {
            strokes[strokes.count - 1] = Stroke(
                points: currentStrokePoints,
                color: last.color,
                width: last.width,
                isEraser: last.isEraser
            )
        } else {
            strokes.append(Stroke(
                points: currentStrokePoints,
                color: brushColor,
                width: CGFloat(brushWidth),
                isEraser: isErasing
            ))
        }
    }

    private func commitDraw() {
        guard let cg = Renderer.rasterizeStrokes(
            strokes.filter { !$0.isEraser },
            canvasSize: canvasPixelSize,
            displayRect: canvasDisplayRect
        ) else { return }
        let layer = Layer(name: "Dibujo", content: LayerContent(image: cg))
        layers.append(layer)
        activeLayerID = layer.id
    }

    private func commitErase() {
        guard let active = activeLayer,
              let base = active.content.cgImage(),
              let cg = applyErase(base) else { return }
        active.content = LayerContent(image: cg)
    }

    private func applyErase(_ base: CGImage) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: base.width,
            height: base.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))

        let scaleX = CGFloat(base.width) / canvasDisplayRect.width
        let scaleY = CGFloat(base.height) / canvasDisplayRect.height

        for stroke in strokes where stroke.isEraser && stroke.points.count >= 2 {
            let path = CGMutablePath()
            let first = CGPoint(
                x: (stroke.points[0].x - canvasDisplayRect.minX) * scaleX,
                y: CGFloat(base.height) - (stroke.points[0].y - canvasDisplayRect.minY) * scaleY
            )
            path.move(to: first)
            for p in stroke.points.dropFirst() {
                path.addLine(to: CGPoint(
                    x: (p.x - canvasDisplayRect.minX) * scaleX,
                    y: CGFloat(base.height) - (p.y - canvasDisplayRect.minY) * scaleY
                ))
            }
            ctx.setBlendMode(.clear)
            ctx.addPath(path)
            ctx.setLineWidth(stroke.width * scaleX)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            ctx.setBlendMode(.normal)
        }
        return ctx.makeImage()
    }

    // MARK: - Render

    /// Tamaño en píxeles del lienzo compuesto (resolución base).
    var canvasPixelSize: CGSize {
        let extent = Renderer.imageExtent(for: layers)
        return CGSize(width: extent.width, height: extent.height)
    }

    /// Rect (en coords de vista, top-left) donde se dibuja el lienzo en el canvas.
    var canvasDisplayRect: CGRect = .zero

    func render() {
        renderedImage = Renderer.renderedImage(
            layers: layers,
            adjustments: adjustments,
            effect: effect,
            effectIntensity: effectIntensity,
            crop: crop
        )
    }

    // MARK: - Undo / Redo

    private func captureSnapshot() -> Snapshot {
        Snapshot(
            layers: layers.map { $0.snapshotCopy() },
            adjustments: adjustments,
            crop: crop,
            effect: effect
        )
    }

    private func restore(_ snapshot: Snapshot) {
        layerNaturalSizes.removeAll()
        layers = snapshot.layers
        adjustments = snapshot.adjustments
        crop = snapshot.crop
        effect = snapshot.effect
        activeLayerID = layers.last?.id
        updateUndoState()
    }

    func pushSnapshot() {
        layerNaturalSizes.removeAll()
        undoStack.append(captureSnapshot())
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
        redoStack.removeAll()
        updateUndoState()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(captureSnapshot())
        restore(last)
        render()
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        undoStack.append(captureSnapshot())
        restore(last)
        render()
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Persistencia de proyecto (NSKeyedArchiver)

    func saveProject(to url: URL) {
        let archived = NSKeyedArchiver.archivedData(withRootObject: self)
        try? archived.write(to: url)
    }

    func loadProject(from url: URL) {
        guard let archived = try? Data(contentsOf: url),
              let decoded = NSKeyedUnarchiver.unarchiveObject(with: archived) as? EditorViewModel else { return }
        layers = decoded.layers
        adjustments = decoded.adjustments
        crop = decoded.crop
        effect = decoded.effect
        effectIntensity = decoded.effectIntensity
        activeTool = decoded.activeTool
        activeLayerID = decoded.activeLayerID
        render()
    }

    // MARK: - NSCoding

    private enum CodingKeys: String {
        case layers, adjustments, crop, effect, effectIntensity, activeTool, activeLayerID, editorTitle, brushColor, brushWidth
    }

    func encode(with coder: NSCoder) {
        coder.encode(layers, forKey: "layers")
        coder.encode(adjustments, forKey: "adjustments")
        coder.encode(crop, forKey: "crop")
        coder.encode(effect.rawValue, forKey: "effect")
        coder.encode(effectIntensity, forKey: "effectIntensity")
        coder.encode(activeTool?.rawValue, forKey: "activeTool")
        coder.encode(activeLayerID?.uuidString, forKey: "activeLayerID")
        coder.encode(editorTitle, forKey: "editorTitle")
        // brushColor y brushWidth son Color y Double, usar workaround
        let nsColor = NSColor(brushColor)
        coder.encode(nsColor, forKey: "brushColor")
        coder.encode(brushWidth, forKey: "brushWidth")
    }

    required convenience init?(coder: NSCoder) {
        self.init()
        layers = coder.decodeObject(forKey: "layers") as? [Layer] ?? []
        adjustments = coder.decodeObject(forKey: "adjustments") as? Adjustments ?? Adjustments()
        crop = coder.decodeObject(forKey: "crop") as? CropState ?? CropState()
        if let effectRaw = coder.decodeObject(forKey: "effect") as? String,
           let effectVal = EffectPreset(rawValue: effectRaw) {
            effect = effectVal
        } else { effect = .none }
        effectIntensity = coder.decodeDouble(forKey: "effectIntensity")
        if let toolRaw = coder.decodeObject(forKey: "activeTool") as? String,
           let toolVal = EditorTool(rawValue: toolRaw) {
            activeTool = toolVal
        }
        if let idStr = coder.decodeObject(forKey: "activeLayerID") as? String {
            activeLayerID = UUID(uuidString: idStr)
        }
        editorTitle = coder.decodeObject(forKey: "editorTitle") as? String ?? "Nuevo proyecto"
        if let nsColor = coder.decodeObject(forKey: "brushColor") as? NSColor {
            brushColor = Color(nsColor: nsColor)
        }
        brushWidth = coder.decodeDouble(forKey: "brushWidth")
    }
}