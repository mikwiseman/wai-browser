import SwiftUI

@MainActor final class BrowserDownloads: ObservableObject {
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
    @Published private(set) var files: [URL] = []
    @Published private(set) var activeCount = 0
    @Published private(set) var error: String?
    func refresh(activeCount: Int) {
        self.activeCount = activeCount
        files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
    func remove(_ indexes: IndexSet) {
        for file in indexes.map({ files[$0] }) {
            do { try FileManager.default.removeItem(at: file) }
            catch { self.error = "Не удалось удалить файл." }
        }
        refresh(activeCount: activeCount)
    }
}

struct DownloadsView: View {
    @ObservedObject var store: BrowserDownloads
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if store.activeCount > 0 { Label("Загружается файлов: \(store.activeCount)", systemImage: "arrow.down.circle") }
                ForEach(store.files, id: \.self) { file in
                    Button { open(file) } label: { Label(file.lastPathComponent, systemImage: "doc").foregroundStyle(.primary) }.buttonStyle(.plain)
                }.onDelete(perform: store.remove)
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }
            .overlay {
                if store.files.isEmpty && store.activeCount == 0 { ContentUnavailableView("Нет загрузок", systemImage: "arrow.down.circle", description: Text("Загруженные файлы появятся здесь.")) }
            }
            .navigationTitle("Загрузки").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
