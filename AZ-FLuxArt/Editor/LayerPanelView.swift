import SwiftUI

struct LayerPanelView: View {
    @ObservedObject var viewModel: EditorViewModel
    var onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Capas")
                    .font(.headline)
                Spacer()
                Button { viewModel.duplicateActiveLayer() } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.activeLayer == nil)
                .help("Duplicar capa activa")
                Button { viewModel.deleteActiveLayer() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.activeLayer == nil)
                .help("Eliminar capa activa")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    if viewModel.layers.isEmpty {
                        Text("Sin capas")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 40)
                    }
                    ForEach(Array(viewModel.layers.enumerated()).reversed(), id: \.element.id) { index, layer in
                        LayerCell(
                            layer: layer,
                            index: index,
                            total: viewModel.layers.count,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(8)
            }

            Divider()

            HStack(spacing: 6) {
                Button { onImport() } label: {
                    Label("Imagen", systemImage: "photo")
                }
                Button { viewModel.selectTool(.text) } label: {
                    Label("Texto", systemImage: "textformat")
                }
                Button { viewModel.selectTool(.stickers) } label: {
                    Label("Sticker", systemImage: "face.smiling")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct LayerCell: View {
    @ObservedObject var layer: Layer
    let index: Int
    let total: Int
    @ObservedObject var viewModel: EditorViewModel

    private var isActive: Bool {
        viewModel.activeLayerID == layer.id
    }

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(layer.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Slider(
                    value: Binding(
                        get: { layer.opacity },
                        set: { viewModel.setLayerOpacity(layer, $0) }
                    ),
                    in: 0.05...1
                )
                .controlSize(.mini)
                .disabled(layer.isLocked)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.toggleLayerVisibility(layer)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)

            VStack(spacing: 2) {
                Button {
                    viewModel.moveLayer(layer, by: 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == total - 1)
                Button {
                    viewModel.moveLayer(layer, by: -1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
            }
            .controlSize(.mini)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.activeLayerID = layer.id
        }
        .contextMenu {
            Button("Duplicar") { viewModel.duplicateActiveLayer() }
            Button("Restablecer transformación") { viewModel.resetActiveLayerTransform() }
                .disabled(layer.transform == .identity)
            Button("Eliminar", role: .destructive) { viewModel.deleteLayer(layer) }
        }
    }

    private var thumbnail: some View {
        Group {
            if let cg = Renderer.cgImage(for: layer.content) {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipped()
            } else {
                Image(systemName: "photo")
            }
        }
        .background(Color.black.opacity(0.15))
    }
}