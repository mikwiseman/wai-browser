import XCTest
@testable import WaiBrowser

@MainActor final class LibraryTests: XCTestCase {
    func testHistoryAndBookmarksPersistWithoutDuplicates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("library.json")
        let library = BrowserLibrary(file: file)
        let url = URL(string: "https://example.org/page?q=hello")!
        library.visit(url, title: "First")
        library.visit(url, title: "Updated")
        library.setBookmark(url, title: "Saved", saved: true)
        library.setBookmark(url, title: "Saved", saved: true)
        library.saveSession([url, nil, URL(string: "https://example.com/")!], selected: 2)
        let restored = BrowserLibrary(file: file)
        XCTAssertEqual(restored.history.count, 1)
        XCTAssertEqual(restored.history.first?.title, "Updated")
        XCTAssertEqual(restored.bookmarks.count, 1)
        XCTAssertEqual(restored.session.urls, [url, nil, URL(string: "https://example.com/")!])
        XCTAssertEqual(restored.session.selected, 2)
        restored.clearHistory()
        let cleared = BrowserLibrary(file: file)
        XCTAssertTrue(cleared.history.isEmpty)
        XCTAssertEqual(cleared.bookmarks.count, 1)
    }

    func testOnlyWebAddressesAreRememberedAndCredentialsAreRemoved() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = BrowserLibrary(file: folder.appendingPathComponent("library.json"))
        for value in ["about:blank", "file:///secret", "javascript:alert(1)", "data:text/plain,secret"] {
            library.visit(URL(string: value)!, title: "Private")
        }
        XCTAssertTrue(library.history.isEmpty)
        library.visit(URL(string: "https://user:password@example.org/page")!, title: "Example")
        XCTAssertEqual(library.history.first?.url.absoluteString, "https://example.org/page")
    }
}
