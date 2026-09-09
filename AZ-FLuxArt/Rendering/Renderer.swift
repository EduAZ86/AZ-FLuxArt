import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import CoreText
import AppKit

@MainActor
enum Renderer {
    static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])

    static func imageExtent(for layers: [Layer]) -> CGRect {
        for layer in layers {
            if layer.content.kind == .image,
               let cg = layer.content.cgImage() {
                return CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            }
        }
        return CGRect(x: 0, y: 0, width: 1024, height: 1024)
    }

    static func cgImage(for content: LayerContent) -> CGImage? {
        return content.cgImage()
    }

    static func ciImage(for content: LayerContent) -> CIImage? {
        guard let cg = cgImage(for: content) else { return nil }
        return CIImage(cgImage: cg)
    }

    /// Compone una sola capa de imagen con su transform sobre un lienzo del tamaño dado
    /// (se usa para recortar "lo que se ve" de la base).
    static func compositedLayer(
        _ cg: CGImage,
        transform: LayerTransform,
        canvasSize: CGSize
    ) -> CGImage? {
        let layer = Layer(name: "base", content: LayerContent(image: cg))
        layer.transform = transform
        let extent = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
        var composite: CIImage?
        guard let layerImage = ciImage(for: layer.content) else { return nil }
        let positioned = transformed(layerImage, by: layer.transform, in: extent)
        composite = positioned.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity)
        ])
        guard let output = composite else { return nil }
        return context.createCGImage(output.cropped(to: extent), from: extent)
    }

    /// Compone todas las capas visibles + ajustes + efecto + recorte.
    /// Devuelve el CGImage final listo para mostrar (orientación correcta).
    static func renderedImage(
        layers: [Layer],
        adjustments: Adjustments,
        effect: EffectPreset,
        effectIntensity: Double,
        crop: CropState?
    ) -> CGImage? {
        let extent = imageExtent(for: layers)
        var composite: CIImage?

        for layer in layers where layer.isVisible {
            guard let layerImage = ciImage(for: layer.content) else { continue }
            let positioned = transformed(layerImage, by: layer.transform, in: extent)
            let alpha = positioned.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity)
            ])
            if let existing = composite {
                composite = alpha.composited(over: existing)
            } else {
                composite = alpha
            }
        }

        var output = composite ?? CIImage(color: .clear).cropped(to: extent)
        output = applyAdjustments(output, adjustments)
        if effect != .none {
            output = applyEffect(output, effect, intensity: effectIntensity)
        }
        output = output.cropped(to: extent)

        var renderRect = output.extent.integral

        if let crop, crop.isActive {
            let pixelRect = crop.pixelRect(imageSize: CGSize(width: extent.width, height: extent.height))
            let clipped = output.extent.intersection(pixelRect)
            guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else {
                return context.createCGImage(output, from: renderRect)
            }
            let translated = output.cropped(to: clipped)
                .transformed(by: CGAffineTransform(translationX: -clipped.minX, y: -clipped.minY))
            output = translated
            renderRect = output.extent.integral
        }

        return context.createCGImage(output, from: renderRect)
    }

    /// Ubica una capa según su transform (centro normalizado + escala uniforme + rotación).
    /// El orden de transformaciones aplicado al contenido: mover centro al origen, escalar,
    /// rotar alrededor del centro, trasladar a la posición destino (en píxeles del lienzo).
    private static func transformed(_ image: CIImage, by t: LayerTransform, in extent: CGRect) -> CIImage {
        let cx = extent.width * t.center.x
        let cy = extent.height * t.center.y
        var xform = CGAffineTransform.identity
        xform = xform.translatedBy(x: cx, y: cy)
        xform = xform.rotated(by: t.rotation)
        xform = xform.scaledBy(x: t.scale, y: t.scale)
        xform = xform.translatedBy(x: -image.extent.midX, y: -image.extent.midY)
        return image.transformed(by: xform)
    }

    private static func applyAdjustments(_ image: CIImage, _ adj: Adjustments) -> CIImage {
        var out = image
        if adj.brightness != 0 || abs(adj.contrast - 1) > 0.001 || abs(adj.saturation - 1) > 0.001 {
            out = out.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: adj.brightness,
                kCIInputContrastKey: adj.contrast,
                kCIInputSaturationKey: adj.saturation,
            ])
        }
        if adj.exposure != 0 {
            out = out.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: adj.exposure])
        }
        if adj.temperature != 0 {
            let neutral = CIVector(x: 6500.0 + adj.temperature * 10, y: 0)
            out = out.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": neutral,
                "inputTargetNeutral": CIVector(x: 6500, y: 0),
            ])
        }
        return out
    }

    private static func applyEffect(_ image: CIImage, _ effect: EffectPreset, intensity: Double) -> CIImage {
        let i = max(0, min(1, intensity))
        switch effect {
        case .none:
            return image
        case .mono:
            return image.applyingFilter("CIPhotoEffectMono")
        case .sepia:
            return image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: i])
        case .noir:
            return image.applyingFilter("CIPhotoEffectNoir")
        case .vignette:
            return image.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: i * 2.0,
                kCIInputRadiusKey: image.extent.width * 0.8,
            ])
        case .bloom:
            return image.applyingFilter("CIBloom", parameters: [
                kCIInputIntensityKey: i * 2.0,
                kCIInputRadiusKey: image.extent.width * 0.1,
            ])
        case .pixellate:
            return image.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: max(4, image.extent.width * 0.02 * i)
            ])
        case .gloom:
            return image.applyingFilter("CIGloom", parameters: [
                kCIInputIntensityKey: i * 2.0,
                kCIInputRadiusKey: image.extent.width * 0.2,
            ])
        case .comic:
            return image.applyingFilter("CIComicEffect")
        }
    }

    static func renderTextToCGImage(_ content: TextLayerContent) -> CGImage? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let string = NSAttributedString(string: content.text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: content.fontSize),
            .foregroundColor: NSColor(cgColor: content.color.cgColor ?? NSColor.black.cgColor),
            .paragraphStyle: paragraph,
        ])
        return rasterize(string, padding: 24)
    }

    static func renderStickerToCGImage(_ emoji: String) -> CGImage? {
        let string = NSAttributedString(string: emoji, attributes: [
            .font: NSFont.systemFont(ofSize: 96),
        ])
        return rasterize(string, padding: 12)
    }

    private static func rasterize(_ string: NSAttributedString, padding: CGFloat) -> CGImage? {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let constraints = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        var fitRange = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), nil, constraints, &fitRange)
        guard suggested.width > 0, suggested.height > 0 else { return nil }
        let w = ceil(suggested.width) + padding * 2
        let h = ceil(suggested.height) + padding * 2
        guard let ctx = CGContext(
            data: nil,
            width: Int(w),
            height: Int(h),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.textMatrix = .identity
        let path = CGMutablePath()
        path.addRect(CGRect(x: padding, y: padding, width: suggested.width, height: suggested.height))
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, ctx)
        return ctx.makeImage()
    }

    /// Rasteriza trazos (dibujo) sobre un lienzo transparente del tamaño indicado.
    /// - Parameter displayRect: rect del lienzo en coordenadas de vista (top-left).
    static func rasterizeStrokes(
        _ strokes: [Stroke],
        canvasSize: CGSize,
        displayRect: CGRect
    ) -> CGImage? {
        guard !strokes.isEmpty else { return nil }
        let scaleX = canvasSize.width / displayRect.width
        let scaleY = canvasSize.height / displayRect.height
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(origin: .zero, size: canvasSize))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for stroke in strokes where stroke.points.count >= 2 {
            let path = CGMutablePath()
            let first = CGPoint(
                x: (stroke.points[0].x - displayRect.minX) * scaleX,
                y: canvasSize.height - (stroke.points[0].y - displayRect.minY) * scaleY
            )
            path.move(to: first)
            for p in stroke.points.dropFirst() {
                path.addLine(to: CGPoint(
                    x: (p.x - displayRect.minX) * scaleX,
                    y: canvasSize.height - (p.y - displayRect.minY) * scaleY
                ))
            }

            if stroke.isEraser {
                ctx.setBlendMode(.clear)
                ctx.addPath(path)
                ctx.setLineWidth(stroke.width * scaleX)
                ctx.strokePath()
                ctx.setBlendMode(.normal)
            } else {
                ctx.setBlendMode(.normal)
                ctx.setStrokeColor(stroke.color.cgColor ?? NSColor.black.cgColor)
                ctx.addPath(path)
                ctx.setLineWidth(stroke.width * scaleX)
                ctx.strokePath()
            }
        }

        return ctx.makeImage()
    }

    /// Aplica transformaciones geométricas simples a una capa de imagen.
    static func transformImage(_ cg: CGImage, flipHorizontal: Bool, flipVertical: Bool, rotateDegrees: Int) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        if rotateDegrees % 180 != 0 {
            rect = CGRect(x: 0, y: 0, width: cg.height, height: cg.width)
        }
        guard let ctx = CGContext(
            data: nil,
            width: Int(rect.width),
            height: Int(rect.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let rad = Double(rotateDegrees % 360) * .pi / 180
        var transform = CGAffineTransform.identity

        // Mover el origen al centro para rotar/flip alrededor del centro.
        // Nota: ángulo negado para que positivo = horario (el contexto CG dibuja al revés).
        transform = transform
            .translatedBy(x: rect.width / 2, y: rect.height / 2)
            .rotated(by: -rad)
        if flipHorizontal { transform = transform.scaledBy(x: -1, y: 1) }
        if flipVertical { transform = transform.scaledBy(x: 1, y: -1) }
        transform = transform.translatedBy(x: -CGFloat(cg.width) / 2, y: -CGFloat(cg.height) / 2)

        ctx.concatenate(transform)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage()
    }
}