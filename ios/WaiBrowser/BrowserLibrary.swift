import Foundation
import Combine

struct BrowserEntry: Codable, Identifiable {
    var url: URL
    var title: String
    var date: Date
    var id: String { url.absoluteString }
}

struct BrowserSession: Codable {
    var urls: [URL?] = []
    var selected = 0
}

@MainActor final class BrowserLibrary: ObservableObject {
    private struct Contents: Codable {
        var history: [BrowserEntry] = []
        var bookmarks: [BrowserEntry] = []
        var session = BrowserSession()
    }
    @Published private var contents: Contents
    @Published private(set) var saveError: String?
    private let file: URL
    var history: [BrowserEntry] { contents.history }
    var bookmarks: [BrowserEntry] { contents.bookmarks }
    var session: BrowserSession { contents.session }

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("browser-library.json")
        if let data = try? Data(contentsOf: self.file), let saved = try? JSONDecoder().decode(Contents.self, from: data) { contents = saved }
        else { contents = Contents() }
    }
    static func webURL(_ url: URL?) -> URL? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.user = nil; parts.password = nil
        return parts.url
    }
    func visit(_ url: URL, title: String?) {
        guard let url = Self.webURL(url) else { return }
        contents.history.removeAll { $0.url == url }
        contents.history.insert(BrowserEntry(url: url, title: title?.isEmpty == false ? title! : url.host!, date: Date()), at: 0)
        if contents.history.count > 5000 { contents.history.removeLast(contents.history.count - 5000) }
        save()
    }
    func isBookmarked(_ url: URL?) -> Bool { contents.bookmarks.contains { $0.url == Self.webURL(url) } }
    func updateTitle(_ title: String?, for url: URL?) {
        guard let title, !title.isEmpty, let url = Self.webURL(url),
              let index = contents.history.firstIndex(where: { $0.url == url }), contents.history[index].title != title else { return }
        contents.history[index].title = title; save()
    }
    func setBookmark(_ url: URL, title: String?, saved: Bool) {
        guard let url = Self.webURL(url) else { return }
        contents.bookmarks.removeAll { $0.url == url }
        if saved { contents.bookmarks.insert(BrowserEntry(url: url, title: title?.isEmpty == false ? title! : url.host!, date: Date()), at: 0) }
        save()
    }
    func removeHistory(_ ids: Set<String>) { contents.history.removeAll { ids.contains($0.id) }; save() }
    func clearHistory() { contents.history.removeAll(); save() }
    func saveSession(_ urls: [URL?], selected: Int) {
        contents.session = BrowserSession(urls: urls.map(Self.webURL), selected: min(max(0, selected), max(0, urls.count - 1)))
        save()
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(contents).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saveError = nil
        } catch { saveError = "Не удалось сохранить историю и вкладки. Проверьте свободное место." }
    }
}
