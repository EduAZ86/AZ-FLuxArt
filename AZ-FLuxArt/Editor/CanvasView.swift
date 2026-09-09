import SwiftUI

struct CanvasView: View {
    let image: CGImage
    @ObservedObject var viewModel: EditorViewModel

    @State private var userScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var gestureStartScale: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let base = fitScale(in: geo.size)
            let imgSize = CGSize(
                width: CGFloat(image.width) * base * userScale,
                height: CGFloat(image.height) * base * userScale
            )
            let imgRect = CGRect(
                x: geo.size.width / 2 + offset.width - imgSize.width / 2,
                y: geo.size.height / 2 + offset.height - imgSize.height / 2,
                width: imgSize.width,
                height: imgSize.height
            )

            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imgSize.width, height: imgSize.height)
                    .position(x: geo.size.width / 2 + offset.width,
                              y: geo.size.height / 2 + offset.height)

                if viewModel.activeTool == .crop && viewModel.crop.isActive {
                    CropOverlay(
                        frame: imgRect,
                        aspectRatio: viewModel.crop.aspectRatio,
                        rect: Binding(
                            get: { viewModel.crop.rect },
                            set: { viewModel.crop.rect = $0 }
                        )
                    )
                }

                if viewModel.activeTool == .draw || viewModel.activeTool == .erase {
                    DrawOverlay(imageFrame: imgRect, viewModel: viewModel)
                }

                if viewModel.activeTool == nil,
                   let layer = viewModel.activeLayer,
                   layer.isVisible,
                   !layer.isLocked {
                    TransformOverlay(
                        frame: imgRect,
                        layer: layer,
                        canvasPixelSize: viewModel.canvasPixelSize,
                        naturalPixelSize: viewModel.naturalPixelSize(for: layer),
                        onTransformChange: { viewModel.updateActiveLayerTransform($0) },
                        onTransformCommit: { viewModel.commitActiveLayerTransform() },
                        onDeselect: { viewModel.deselectLayer() }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(panGestureIfIdle, including: isToolActive ? .none : .all)
            .gesture(magnifyGestureIfIdle, including: isToolActive ? .none : .all)
            .onTapGesture {
                if viewModel.activeTool == nil {
                    viewModel.deselectLayer()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                zoomControls(geo: geo)
            }
            .onAppear {
                resetView(in: geo.size)
                viewModel.canvasDisplayRect = CGRect(origin: .zero, size: imgSize)
            }
            .onChange(of: imgSize) { _, _ in
                viewModel.canvasDisplayRect = CGRect(origin: .zero, size: imgSize)
            }
            .onChange(of: CGSize(width: image.width, height: image.height)) { _, _ in
                resetView(in: geo.size)
            }
        }
    }

    private var isToolActive: Bool {
        viewModel.activeTool != nil
    }

    private var panGestureIfIdle: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isToolActive else { return }
                let dx = value.translation.width - lastPan.width
                let dy = value.translation.height - lastPan.height
                offset.width += dx
                offset.height += dy
                lastPan = value.translation
            }
            .onEnded { _ in lastPan = .zero }
    }

    private var magnifyGestureIfIdle: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !isToolActive else { return }
                if gestureStartScale == nil { gestureStartScale = userScale }
                userScale = clamp((gestureStartScale ?? 1) * value.magnification)
            }
            .onEnded { _ in gestureStartScale = nil }
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        guard w > 0, h > 0 else { return 1 }
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / w, size.height / h)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.2), 8)
    }

    private func resetView(in size: CGSize) {
        userScale = 1
        offset = .zero
    }

    private func zoomControls(geo: GeometryProxy) -> some View {
        HStack(spacing: 4) {
            Button { userScale = clamp(userScale * 1.25) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Acercar")

            Button { userScale = clamp(userScale / 1.25) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Alejar")

            Button { resetView(in: geo.size) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Ajustar a ventana")
        }
        .buttonStyle(.borderless)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }
}

// MARK: - Overlay de recorte

struct CropOverlay: View {
    var frame: CGRect
    var aspectRatio: CGFloat?
    @Binding var rect: CGRect?

    private enum DragMode: Equatable {
        case create
        case move
        case resize(Corner)
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    @State private var dragMode: DragMode?
    @State private var anchor: CGPoint?
    @State private var startRect: CGRect?
    @State private var draft: CGRect?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let current = draft ?? rect {
                    let r = rectInFrame(current)
                    dimRegion(width: frame.width, height: r.minY, x: 0, y: 0)
                    dimRegion(width: r.minX, height: r.height, x: 0, y: r.minY)
                    dimRegion(width: frame.width - r.maxX, height: r.height, x: r.maxX, y: r.minY)
                    dimRegion(width: frame.width, height: frame.height - r.maxY, x: 0, y: r.maxY)

                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)

                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)

                    ruleOfThirds(in: r)
                    cornerHandles(in: r)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(geo: geo))
            .onDisappear {
                draft = nil
                anchor = nil
                dragMode = nil
                startRect = nil
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private func ruleOfThirds(in r: CGRect) -> some View {
        Canvas { ctx, _ in
            let step = CGSize(width: r.width / 3, height: r.height / 3)
            for i in 1...2 {
                var vline = Path()
                vline.move(to: CGPoint(x: r.minX + step.width * CGFloat(i), y: r.minY))
                vline.addLine(to: CGPoint(x: r.minX + step.width * CGFloat(i), y: r.maxY))
                ctx.stroke(vline, with: .color(.white.opacity(0.45)), lineWidth: 0.5)
                var hline = Path()
                hline.move(to: CGPoint(x: r.minX, y: r.minY + step.height * CGFloat(i)))
                hline.addLine(to: CGPoint(x: r.maxX, y: r.minY + step.height * CGFloat(i)))
                ctx.stroke(hline, with: .color(.white.opacity(0.45)), lineWidth: 0.5)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .allowsHitTesting(false)
    }

    private func cornerHandles(in r: CGRect) -> some View {
        ForEach(Corner.allCases, id: \.self) { corner in
            let p = point(for: corner, in: r)
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                .frame(width: 14, height: 14)
                .position(x: p.x, y: p.y)
        }
    }

    private func point(for corner: Corner, in r: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func dimRegion(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: max(0, width), height: max(0, height))
            .position(x: x + max(0, width) / 2, y: y + max(0, height) / 2)
    }

    private func rectInFrame(_ r: CGRect) -> CGRect {
        CGRect(
            x: r.minX * frame.width,
            y: r.minY * frame.height,
            width: r.width * frame.width,
            height: r.height * frame.height
        )
    }

    private func normalized(_ point: CGPoint, in geo: GeometryProxy) -> CGPoint {
        CGPoint(
            x: point.x / geo.size.width,
            y: point.y / geo.size.height
        )
    }

    private func dragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = normalized(value.location, in: geo)
                guard p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 else { return }

                if anchor == nil {
                    let start = normalized(value.startLocation, in: geo)
                    anchor = start
                    dragMode = mode(for: start)
                    startRect = rect
                    if dragMode == .create {
                        draft = CGRect(x: start.x, y: start.y, width: 0, height: 0)
                    }
                }

                guard let mode = dragMode, let start = anchor else { return }
                switch mode {
                case .create:
                    draft = makeRect(from: start, to: p)
                case .move:
                    moveRect(by: CGPoint(x: p.x - start.x, y: p.y - start.y))
                case let .resize(corner):
                    if let r = startRect {
                        draft = resizedRect(from: r, corner: corner, to: p)
                    }
                }
            }
            .onEnded { _ in
                if let d = draft, d.width > 0.01, d.height > 0.01 {
                    rect = d
                }
                draft = nil
                anchor = nil
                dragMode = nil
                startRect = nil
            }
    }

    private func mode(for p: CGPoint) -> DragMode {
        guard let r = rect, r.width > 0.01, r.height > 0.01 else { return .create }
        let tx = 12 / frame.width
        let ty = 12 / frame.height
        for corner in Corner.allCases {
            let c = point(for: corner, in: r)
            if abs(p.x - c.x) <= tx && abs(p.y - c.y) <= ty {
                return .resize(corner)
            }
        }
        if r.insetBy(dx: -0.002, dy: -0.002).contains(p) {
            return .move
        }
        return .create
    }

    private func makeRect(from start: CGPoint, to p: CGPoint) -> CGRect {
        var w = abs(p.x - start.x)
        var h = abs(p.y - start.y)
        if let ratio = aspectRatio, ratio > 0 {
            if h * ratio > w { w = h * ratio } else { h = w / ratio }
        }
        var x = min(start.x, p.x)
        var y = min(start.y, p.y)
        if p.x < start.x { x = start.x - w }
        if p.y < start.y { y = start.y - h }
        x = max(0, min(x, 1 - w))
        y = max(0, min(y, 1 - h))
        if x < 0 { x = 0 }
        if y < 0 { y = 0 }
        if x + w > 1 { w = 1 - x }
        if y + h > 1 { h = 1 - y }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func moveRect(by delta: CGPoint) {
        guard let r = startRect else { return }
        let x = max(0, min(r.minX + delta.x, 1 - r.width))
        let y = max(0, min(r.minY + delta.y, 1 - r.height))
        draft = CGRect(x: x, y: y, width: r.width, height: r.height)
    }

    private func resizedRect(from r: CGRect, corner: Corner, to p: CGPoint) -> CGRect {
        let fixed: CGPoint
        switch corner {
        case .topLeft: fixed = CGPoint(x: r.maxX, y: r.maxY)
        case .topRight: fixed = CGPoint(x: r.minX, y: r.maxY)
        case .bottomLeft: fixed = CGPoint(x: r.maxX, y: r.minY)
        case .bottomRight: fixed = CGPoint(x: r.minX, y: r.minY)
        }
        var w = abs(p.x - fixed.x)
        var h = abs(p.y - fixed.y)
        if let ratio = aspectRatio, ratio > 0 {
            if h * ratio > w { w = h * ratio } else { h = w / ratio }
        }
        let maxW: CGFloat
        let maxH: CGFloat
        switch corner {
        case .topLeft: maxW = fixed.x; maxH = fixed.y
        case .topRight: maxW = 1 - fixed.x; maxH = fixed.y
        case .bottomLeft: maxW = fixed.x; maxH = 1 - fixed.y
        case .bottomRight: maxW = 1 - fixed.x; maxH = 1 - fixed.y
        }
        if let ratio = aspectRatio, ratio > 0 {
            w = min(w, maxW, maxH * ratio)
            h = w / ratio
        } else {
            w = min(w, maxW)
            h = min(h, maxH)
        }
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft: x = fixed.x - w; y = fixed.y - h
        case .topRight: x = fixed.x; y = fixed.y - h
        case .bottomLeft: x = fixed.x - w; y = fixed.y
        case .bottomRight: x = fixed.x; y = fixed.y
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Overlay de dibujo / borrador

struct DrawOverlay: View {
    var imageFrame: CGRect
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        Canvas { ctx, _ in
            for stroke in viewModel.strokes {
                var path = Path()
                if let first = stroke.points.first {
                    path.move(to: first)
                    for p in stroke.points.dropFirst() {
                        path.addLine(to: p)
                    }
                }
                if stroke.isEraser {
                    ctx.stroke(
                        path,
                        with: .color(.red.opacity(0.45)),
                        style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
                    )
                } else {
                    ctx.stroke(
                        path,
                        with: .color(stroke.color),
                        style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .frame(width: imageFrame.width, height: imageFrame.height)
        .position(x: imageFrame.midX, y: imageFrame.midY)
        .contentShape(Rectangle())
        .gesture(drawGesture)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = CGPoint(x: value.location.x, y: value.location.y)
                guard p.x >= 0, p.x <= imageFrame.width, p.y >= 0, p.y <= imageFrame.height else { return }
                if viewModel.currentStrokePoints.isEmpty {
                    let s = CGPoint(x: value.startLocation.x, y: value.startLocation.y)
                    viewModel.beginStroke(at: s, isEraser: viewModel.activeTool == .erase)
                } else {
                    viewModel.appendStrokePoint(p)
                }
            }
            .onEnded { _ in
                viewModel.currentStrokePoints.removeAll()
            }
    }
}

// MARK: - Overlay de transformación de capa (mover / escalar / rotar)

struct TransformOverlay: View {
    let frame: CGRect
    let layer: Layer
    let canvasPixelSize: CGSize
    let naturalPixelSize: CGSize
    var onTransformChange: (LayerTransform) -> Void
    var onTransformCommit: () -> Void
    var onDeselect: () -> Void

    private enum DragMode {
        case move, scale, rotate
    }

    @State private var dragMode: DragMode?
    @State private var startLocal: CGPoint?
    @State private var startTransform: LayerTransform?

    private var displayScale: CGFloat {
        guard canvasPixelSize.width > 0 else { return 1 }
        return frame.width / canvasPixelSize.width
    }

    private var naturalDisplaySize: CGSize {
        CGSize(
            width: naturalPixelSize.width * displayScale,
            height: naturalPixelSize.height * displayScale
        )
    }

    private var displaySize: CGSize {
        CGSize(
            width: naturalDisplaySize.width * layer.transform.scale,
            height: naturalDisplaySize.height * layer.transform.scale
        )
    }

    private var centerLocal: CGPoint {
        CGPoint(
            x: layer.transform.center.x * frame.width,
            y: layer.transform.center.y * frame.height
        )
    }

    var body: some View {
        GeometryReader { geo in
            let cs = corners()
            let box = boxPath(cs)
            ZStack {
                box.fill(Color.accentColor.opacity(0.05))
                box.stroke(Color.white, lineWidth: 1.5)
                box.stroke(Color.black.opacity(0.3), lineWidth: 0.5)

                ForEach(0..<4, id: \.self) { i in
                    handleSquare(at: cs[i])
                }
                handleCircle(at: rotationHandle(), isRotation: true)
            }
            .contentShape(hitShape(cs))
            .gesture(dragGesture)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .onDisappear {
            dragMode = nil
            startLocal = nil
            startTransform = nil
        }
    }

    private func boxPath(_ cs: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: cs[0])
        for p in cs.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    private func hitShape(_ cs: [CGPoint]) -> Path {
        var path = boxPath(cs)
        let rot = rotationHandle()
        path.addEllipse(in: CGRect(x: rot.x - 18, y: rot.y - 18, width: 36, height: 36))
        return path
    }

    private func handleSquare(at p: CGPoint) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
            .frame(width: 11, height: 11)
            .position(x: p.x, y: p.y)
    }

    private func handleCircle(at p: CGPoint, isRotation: Bool = false) -> some View {
        Circle()
            .fill(isRotation ? Color.accentColor : Color.white)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
            .frame(width: isRotation ? 12 : 11, height: isRotation ? 12 : 11)
            .position(x: p.x, y: p.y)
    }

    private func corners() -> [CGPoint] {
        let c = centerLocal
        let halfW = displaySize.width / 2
        let halfH = displaySize.height / 2
        let pts = [
            CGPoint(x: c.x - halfW, y: c.y - halfH),
            CGPoint(x: c.x + halfW, y: c.y - halfH),
            CGPoint(x: c.x + halfW, y: c.y + halfH),
            CGPoint(x: c.x - halfW, y: c.y + halfH),
        ]
        return pts.map { rotate($0, around: c, by: layer.transform.rotation) }
    }

    private func rotate(_ p: CGPoint, around c: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = p.x - c.x
        let dy = p.y - c.y
        let ca = cos(angle)
        let sa = sin(angle)
        return CGPoint(x: c.x + dx * ca - dy * sa, y: c.y + dx * sa + dy * ca)
    }

    private func rotationHandle() -> CGPoint {
        let cs = corners()
        let mid = CGPoint(x: (cs[0].x + cs[1].x) / 2, y: (cs[0].y + cs[1].y) / 2)
        let c = centerLocal
        let dx = mid.x - c.x
        let dy = mid.y - c.y
        let len = max(sqrt(dx * dx + dy * dy), 0.001)
        return CGPoint(x: mid.x + dx / len * 24, y: mid.y + dy / len * 24)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func polygonContains(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i]
            let b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xInt = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xInt { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private func mode(at p: CGPoint) -> DragMode? {
        let cs = corners()
        if distance(p, rotationHandle()) <= 16 { return .rotate }
        for corner in cs where distance(p, corner) <= 12 { return .scale }
        if polygonContains(p, cs) { return .move }
        return nil
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if startLocal == nil {
                    startLocal = value.startLocation
                    startTransform = layer.transform
                    dragMode = mode(at: value.startLocation)
                }
                guard let mode = dragMode, let s = startTransform, let start = startLocal else { return }
                switch mode {
                case .move:
                    onTransformChange(moveTransform(s, start: start, to: value.location))
                case .scale:
                    onTransformChange(scaleTransform(s, to: value.location))
                case .rotate:
                    onTransformChange(rotateTransform(s, to: value.location))
                }
            }
            .onEnded { _ in
                onTransformCommit()
                dragMode = nil
                startLocal = nil
                startTransform = nil
            }
    }

    private func moveTransform(_ s: LayerTransform, start: CGPoint, to p: CGPoint) -> LayerTransform {
        var t = s
        let dx = (p.x - start.x) / frame.width
        let dy = (p.y - start.y) / frame.height
        t.center = CGPoint(
            x: min(1, max(0, s.center.x + dx)),
            y: min(1, max(0, s.center.y + dy))
        )
        return t
    }

    private func scaleTransform(_ s: LayerTransform, to p: CGPoint) -> LayerTransform {
        let c = centerLocal
        let start = startLocal ?? p
        let d0 = distance(start, c)
        let d1 = distance(p, c)
        guard d0 > 0.001 else { return s }
        var t = s
        t.scale = min(60, max(0.05, s.scale * (d1 / d0)))
        return t
    }

    private func rotateTransform(_ s: LayerTransform, to p: CGPoint) -> LayerTransform {
        let c = centerLocal
        let start = startLocal ?? p
        let a0 = atan2(start.y - c.y, start.x - c.x)
        let a1 = atan2(p.y - c.y, p.x - c.x)
        var delta = a1 - a0
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        var t = s
        t.rotation = s.rotation + delta
        return t
    }
}