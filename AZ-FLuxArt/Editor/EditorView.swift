import SwiftUI
import UniformTypeIdentifiers
import AppKit

extension Notification.Name {
    static let showStickerLibrary = Notification.Name("showStickerLibrary")
}

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var showingImporter = false
    @State private var showingStickerLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                canvasArea
                if viewModel.showLayersPanel {
                    Divider()
                    LayerPanelView(viewModel: viewModel, onImport: { openImporter() })
                        .frame(width: 280)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let tool = viewModel.activeTool {
                ToolSheetView(tool: tool, viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                BottomToolbarView(viewModel: viewModel)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                viewModel.importImage(url)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.activeTool)
        .animation(.easeInOut(duration: 0.18), value: viewModel.showLayersPanel)
        .sheet(isPresented: $showingStickerLibrary) {
            StickerLibraryView(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showStickerLibrary)) { notification in
            if notification.object as? EditorViewModel === viewModel {
                showingStickerLibrary = true
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { openImporter() } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("Importar imagen (⌘O)")

            Text("AZ-FLuxArt")
                .font(.headline)
                .foregroundStyle(.tint)

            Text(viewModel.editorTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button { viewModel.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .help("Deshacer (⌘Z)")

            Button { viewModel.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.canRedo)
            .help("Rehacer (⇧⌘Z)")

            Toggle(isOn: $viewModel.showLayersPanel) {
                Image(systemName: "square.3.layers.3d")
            }
            .toggleStyle(.button)
            .help("Panel de capas (L)")

            Button { export() } label: {
                Label("Exportar", systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(viewModel.renderedImage == nil)

            Button { saveProject() } label: {
                Label("Guardar proyecto", systemImage: "externaldrive.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(viewModel.renderedImage == nil)

            Button { openProject() } label: {
                Label("Abrir proyecto", systemImage: "externaldrive.badge.checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("o", modifiers: [.command, .option])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let image = viewModel.renderedImage {
                CanvasView(image: image, viewModel: viewModel)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Arrastrá una imagen acá\no hacé clic en Abrir")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Importar imagen…") { openImporter() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                .foregroundStyle(.tertiary)
        )
    }

    // MARK: - Actions

    private func openImporter() {
        showingImporter = true
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let cg = CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { return }
                DispatchQueue.main.async { [viewModel] in
                    viewModel.addImageLayer(cg, name: "Imagen importada")
                }
            }
            return true
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async { [viewModel] in
                    viewModel.importImage(url)
                }
            }
        }
        return true
    }

    private func export() {
        guard let image = viewModel.renderedImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "AZ-FLuxArt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let ext = url.pathExtension.lowercased()
            let rep = NSBitmapImageRep(cgImage: image)
            let data: Data?
            if ext == "jpg" || ext == "jpeg" {
                data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            } else {
                data = rep.representation(using: .png, properties: [:])
            }
            try? data?.write(to: url)
        }
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "azproject") ?? .data]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = viewModel.editorTitle.isEmpty ? "AZ-FLuxArt" : viewModel.editorTitle
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            viewModel.saveProject(to: url)
        }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "azproject") ?? .data]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            viewModel.loadProject(from: url)
        }
    }
}