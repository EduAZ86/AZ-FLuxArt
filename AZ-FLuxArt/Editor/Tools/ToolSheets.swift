import SwiftUI

// MARK: - Recortar

struct CropSheetView: View {
    @ObservedObject var viewModel: EditorViewModel

    private let ratios: [(String, CropState.Mode)] = [
        ("Libre", .free),
        ("1:1", .square),
        ("4:5", .ratio(width: 4, height: 5)),
        ("5:4", .ratio(width: 5, height: 4)),
        ("3:2", .ratio(width: 3, height: 2)),
        ("2:3", .ratio(width: 2, height: 3)),
        ("16:9", .ratio(width: 16, height: 9)),
        ("9:16", .ratio(width: 9, height: 16)),
    ]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(ratios, id: \.0) { label, mode in
                Button {
                    viewModel.crop.mode = mode
                    if let r = viewModel.crop.rect {
                        viewModel.crop.rect = fitRect(r, to: mode)
                    }
                } label: {
                    Text(label)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(viewModel.crop.mode == mode
                              ? Color.accentColor.opacity(0.2)
                              : Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                )
            }

            Spacer()

            Text("Arrastrá sobre la imagen para elegir el recorte")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Restablecer") {
                viewModel.crop.rect = nil
            }
            .disabled(viewModel.crop.rect == nil)
        }
        .padding(16)
    }

    /// Re-encaja un recorte existente al nuevo ratio, anclado al centro y clampeado a la imagen.
    private func fitRect(_ r: CGRect, to mode: CropState.Mode) -> CGRect {
        let ratio: CGFloat?
        switch mode {
        case .free: ratio = nil
        case .square: ratio = 1
        case let .ratio(w, h): ratio = CGFloat(w / h)
        }
        guard let ratio, ratio > 0, r.width > 0.001, r.height > 0.001 else { return r }
        let cx = r.midX
        let cy = r.midY
        var w = r.width
        var h = w / ratio
        if h > 1 { h = 1; w = h * ratio }
        if w > 1 { w = 1; h = w / ratio }
        let x = max(0, min(cx - w / 2, 1 - w))
        let y = max(0, min(cy - h / 2, 1 - h))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Ajustar

struct AdjustSheetView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 20) {
            LabeledSlider(title: "Brillo", value: $viewModel.adjustments.brightness, range: -1...1)
            LabeledSlider(title: "Contraste", value: $viewModel.adjustments.contrast, range: 0...2)
            LabeledSlider(title: "Saturación", value: $viewModel.adjustments.saturation, range: 0...2)
            LabeledSlider(title: "Exposición", value: $viewModel.adjustments.exposure, range: -2...2)
            LabeledSlider(title: "Temperatura", value: $viewModel.adjustments.temperature, range: -100...100)
            Button("Reset") {
                viewModel.adjustments.reset()
            }
        }
        .padding(16)
        .onChange(of: viewModel.adjustments) { _, _ in
            viewModel.render()
        }
    }
}

// MARK: - Efectos

struct EffectsSheetView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EffectPreset.allCases) { preset in
                        Button {
                            viewModel.effect = preset
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: preset.systemImage)
                                    .font(.system(size: 18))
                                Text(preset.label)
                                    .font(.caption)
                            }
                            .frame(width: 64)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(viewModel.effect == preset
                                      ? Color.accentColor.opacity(0.2)
                                      : Color.clear)
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()
                .frame(height: 44)

            LabeledSlider(title: "Intensidad", value: $viewModel.effectIntensity, range: 0...1)
        }
        .padding(16)
        .onChange(of: viewModel.effect) { _, _ in viewModel.render() }
        .onChange(of: viewModel.effectIntensity) { _, _ in viewModel.render() }
    }
}

// MARK: - Texto

struct TextSheetView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var text = "Texto"
    @State private var fontSize: Double = 64
    @State private var color: Color = .white

    var body: some View {
        HStack(spacing: 16) {
            TextField("Escribí tu texto…", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { add() }

            LabeledSlider(title: "Tamaño", value: $fontSize, range: 16...220)

            ColorPicker("Color", selection: $color)
                .labelsHidden()
                .help("Color del texto")

            Button("Agregar texto") { add() }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.addTextLayer(TextLayerContent(
            text: trimmed,
            fontSize: CGFloat(fontSize),
            color: color
        ))
        viewModel.dismissTool()
    }
}

// MARK: - Stickers

struct StickersSheetView: View {
    @ObservedObject var viewModel: EditorViewModel

    private let emojis = [
        "😀", "😂", "❤️", "🔥", "✨", "👍", "🎉", "😍",
        "🤣", "😎", "🥳", "😇", "😭", "🥰", "😅", "🤔",
        "🙏", "💯", "🌈", "🦋", "🐶", "🐱", "🌺", "⭐️",
        "🍕", "⚡️", "💫", "🌸", "🎈", "👑", "💎", "🪄",
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        viewModel.addStickerLayer(emoji)
                        viewModel.dismissTool()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Dibujar

struct DrawSheetView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 16) {
            ColorPicker("Color", selection: $viewModel.brushColor)
                .labelsHidden()
                .help("Color del pincel")

            LabeledSlider(title: "Grosor", value: $viewModel.brushWidth, range: 2...60)

            Text("Dibujá sobre la imagen")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Borrar trazos") {
                viewModel.strokes.removeAll()
                viewModel.currentStrokePoints.removeAll()
            }
            .disabled(viewModel.strokes.isEmpty)
        }
        .padding(16)
    }
}

// MARK: - Borrador

struct EraseSheetView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 16) {
            LabeledSlider(title: "Tamaño", value: $viewModel.brushWidth, range: 4...100)

            Text("Arrastrá sobre la capa activa para borrar")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Restablecer trazos") {
                viewModel.strokes.removeAll()
                viewModel.currentStrokePoints.removeAll()
            }
            .disabled(viewModel.strokes.isEmpty)
        }
        .padding(16)
    }
}

// MARK: - Más

struct MoreSheetView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transformar")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ActionButton("Voltear H", "arrow.left.and.right") {
                    viewModel.flipActiveLayer(horizontal: true)
                }
                ActionButton("Voltear V", "arrow.up.and.down") {
                    viewModel.flipActiveLayer(horizontal: false)
                }
                ActionButton("Rotar 90°", "rotate.right") {
                    viewModel.rotateActiveLayer(degrees: 90)
                }
                ActionButton("Rotar -90°", "rotate.left") {
                    viewModel.rotateActiveLayer(degrees: -90)
                }
                ActionButton("Duplicar", "plus.square.on.square") {
                    viewModel.duplicateActiveLayer()
                }
            }
            .disabled(viewModel.activeLayer == nil)

            Divider()

            Text("Stickers")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ActionButton("Biblioteca", "photo.on.rectangle.angled") {
                    NotificationCenter.default.post(name: .showStickerLibrary, object: viewModel)
                }
            }
            .disabled(viewModel.stickers.isEmpty)

            Divider()

            Text("IA (próximamente)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(["AI Enhance", "Quitar fondo", "AI Expand", "AI Replace"], id: \.self) { name in
                    Label(name, systemImage: "sparkles")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                        )
                        .opacity(0.5)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - IA

struct AIUnavailableView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Edición con IA")
                    .font(.subheadline)
                Text("Descargá el modelo desde el menú de IA para habilitar las herramientas inteligentes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - Biblioteca de Stickers

struct StickerLibraryView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Biblioteca de Stickers")
                    .font(.headline)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if viewModel.stickers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No hay stickers guardados")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Creá uno con la herramienta Recortar → 'Crear sticker'")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 12)], spacing: 12) {
                        ForEach(viewModel.stickers) { sticker in
                            StickerLibraryItem(
                                sticker: sticker,
                                onUse: { viewModel.useStickerFromLibrary($0) },
                                onEdit: { viewModel.editSticker($0); dismiss() },
                                onRename: { s, name in viewModel.renameSticker(s, to: name) },
                                onDelete: { viewModel.removeStickerFromLibrary($0) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 300)
    }
}

struct StickerLibraryItem: View {
    let sticker: Layer
    let onUse: (Layer) -> Void
    let onEdit: (Layer) -> Void
    let onRename: (Layer, String) -> Void
    let onDelete: (Layer) -> Void

    @State private var showingRename = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 6) {
            // Miniatura
            if let cg = sticker.content.cgImage() {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }

            Text(sticker.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 80)

            HStack(spacing: 4) {
                Button { onUse(sticker) } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.plain)
                .help("Usar sticker")

                Button { onEdit(sticker) } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Editar sticker")

                Button { showingRename = true; newName = sticker.name } label: {
                    Image(systemName: "textformat")
                }
                .buttonStyle(.plain)
                .help("Renombrar")

                Button(role: .destructive) { onDelete(sticker) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Eliminar")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        )
        .alert("Renombrar sticker", isPresented: $showingRename) {
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { onRename(sticker, newName) }
        }
    }
}