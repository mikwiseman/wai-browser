import SwiftUI

struct LibraryView: View {
    enum Section: String, CaseIterable { case history = "История", bookmarks = "Закладки" }
    @ObservedObject var library: BrowserLibrary
    @State var section: Section
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmClear = false
    private var entries: [BrowserEntry] {
        let values = section == .history ? library.history : library.bookmarks
        return query.isEmpty ? values : values.filter { $0.title.localizedStandardContains(query) || $0.url.absoluteString.localizedStandardContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    Button { open(entry.url) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.title).foregroundStyle(.primary).lineLimit(2)
                            Text(entry.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if section == .history { Text(entry.date, format: .dateTime.day().month().hour().minute()).font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.vertical, 3)
                    }.buttonStyle(.plain).accessibilityLabel(entry.title)
                }.onDelete { offsets in
                    let selected = offsets.map { entries[$0] }
                    if section == .history { library.removeHistory(Set(selected.map(\.id))) }
                    else { for entry in selected { library.setBookmark(entry.url, title: entry.title, saved: false) } }
                }
                if let error = library.saveError { Text(error).foregroundStyle(.red) }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(query.isEmpty ? (section == .history ? "История пуста" : "Нет закладок") : "Ничего не найдено", systemImage: section == .history ? "clock" : "bookmark", description: Text(query.isEmpty ? (section == .history ? "Здесь появятся открытые сайты." : "Сохраните страницу через меню браузера.") : "Попробуйте другой запрос."))
                }
            }
            .searchable(text: $query, prompt: "Название или адрес")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle(section.rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
                if section == .history && !library.history.isEmpty {
                    ToolbarItem(placement: .cancellationAction) { Button("Очистить") { confirmClear = true } }
                }
            }
            .confirmationDialog("Очистить всю историю?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Очистить историю", role: .destructive) { library.clearHistory() }
            } message: { Text("Закладки и открытые вкладки останутся.") }
        }
    }
}
