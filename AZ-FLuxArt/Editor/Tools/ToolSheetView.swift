import SwiftUI

struct ToolSheetView: View {
    let tool: EditorTool
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(tool.label)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .crop: CropSheetView(viewModel: viewModel)
        case .adjust: AdjustSheetView(viewModel: viewModel)
        case .effects: EffectsSheetView(viewModel: viewModel)
        case .text: TextSheetView(viewModel: viewModel)
        case .stickers: StickersSheetView(viewModel: viewModel)
        case .draw: DrawSheetView(viewModel: viewModel)
        case .erase: EraseSheetView(viewModel: viewModel)
        case .more: MoreSheetView(viewModel: viewModel)
        case .ai: AIUnavailableView(viewModel: viewModel)
        }
    }

    private var footer: some View {
        HStack {
            Button(role: .cancel) {
                viewModel.cancelTool()
            } label: {
                Label("Cancelar", systemImage: "xmark")
            }
            Spacer()
            Button {
                viewModel.applyTool()
            } label: {
                Label("Aplicar", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $value, in: range)
                .frame(width: 150)
            Text(String(format: "%.2f", value))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }
}

struct ActionButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    init(_ label: String, _ systemImage: String, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption)
            }
            .frame(width: 72)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        )
    }
}