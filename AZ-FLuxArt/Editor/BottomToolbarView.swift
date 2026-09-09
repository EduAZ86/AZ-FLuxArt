import SwiftUI

struct BottomToolbarView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases) { tool in
                    if tool == .ai {
                        AIToolButton(viewModel: viewModel)
                    } else {
                        ToolButton(tool: tool, viewModel: viewModel)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}

struct AIToolButton: View {
    @ObservedObject var viewModel: EditorViewModel

    var isEnabled: Bool {
        viewModel.aiModelInstalled
    }

    var isActive: Bool {
        viewModel.activeTool == .ai
    }

    var body: some View {
        if isEnabled {
            // Modelo descargado: solo el icono de IA + "IA".
            Button {
                viewModel.selectTool(.ai)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: EditorTool.ai.systemImage)
                        .font(.system(size: 18, weight: .medium))
                    Text(EditorTool.ai.label)
                        .font(.caption)
                        .lineLimit(1)
                }
                .frame(width: 64)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .help("IA")
        } else {
            // Sin modelo: un solo botón compuesto. La parte superior (icono + "IA")
            // se ve deshabilitada y la inferior, habilitada, dice "Descargar modelo".
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: EditorTool.ai.systemImage)
                        .font(.system(size: 15, weight: .medium))
                    Text(EditorTool.ai.label)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(width: 96)
                .padding(.top, 6)
                .padding(.bottom, 3)
                .help("IA — descargá el modelo para habilitarla")

                Button {
                    viewModel.downloadAIModel()
                } label: {
                    HStack(spacing: 3) {
                        if viewModel.isDownloadingAIModel {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text("Descargar modelo")
                                .font(.caption2)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .padding(.vertical, 3)
                    .frame(width: 96)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(viewModel.isDownloadingAIModel)
                .help("Descargar modelo")
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
    }
}

struct ToolButton: View {
    let tool: EditorTool
    @ObservedObject var viewModel: EditorViewModel

    var isActive: Bool {
        viewModel.activeTool == tool
    }

    var body: some View {
        Button {
            viewModel.selectTool(tool)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(tool.label)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 64)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .help(tool.label)
    }
}