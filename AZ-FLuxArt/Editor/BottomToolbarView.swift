import SwiftUI

struct BottomToolbarView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases) { tool in
                    ToolButton(tool: tool, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.bar)
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