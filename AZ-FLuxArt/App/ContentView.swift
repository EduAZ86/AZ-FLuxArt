import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = EditorViewModel()

    var body: some View {
        EditorView(viewModel: viewModel)
    }
}