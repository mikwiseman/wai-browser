import XCTest

@MainActor final class BrowserUITests: XCTestCase {
    func testDownloadListUpdatesWhileOpen() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let address = app.searchFields["address"]
        XCTAssertTrue(address.waitForExistence(timeout: 60))
        let name = UUID().uuidString.lowercased()
        app.buttons["Новая вкладка"].tap()
        address.typeText("http://127.0.0.1:9561/slow.txt?" + name + "\n")
        app.buttons["Меню"].tap()
        let downloads = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Загрузки")).firstMatch
        XCTAssertTrue(downloads.waitForExistence(timeout: 10)); downloads.tap()
        XCTAssertTrue(app.staticTexts["Загружается файлов: 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["slow-" + name + ".txt"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["Загружается файлов: 1"].exists)
        capture("download-completed-while-open")
    }

    func testHistoryBookmarksAndTabsSurviveRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let address = app.searchFields["address"]
        XCTAssertTrue(address.waitForExistence(timeout: 60))
        app.buttons["Новая вкладка"].tap()
        address.tap()
        address.typeText("http://127.0.0.1:9561/\n")
        XCTAssertTrue(app.staticTexts["Wai Browser test"].waitForExistence(timeout: 30))
        app.buttons["Меню"].tap()
        if app.buttons["В закладки"].exists { app.buttons["В закладки"].tap() }
        else { app.buttons["Убрать закладку"].tap(); app.buttons["Меню"].tap(); app.buttons["В закладки"].tap() }
        app.buttons["Меню"].tap()
        app.buttons["История"].tap()
        XCTAssertTrue(app.buttons["Wai Browser test"].waitForExistence(timeout: 10))
        capture("history")
        app.buttons["Готово"].tap()
        app.buttons["Новая вкладка"].tap()
        address.typeText("http://127.0.0.1:9561/second\n")
        XCTAssertTrue(app.staticTexts["Second test page"].waitForExistence(timeout: 15))
        let tabCount = app.buttons["Вкладки"].value as? String
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Second test page"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["Вкладки"].value as? String, tabCount)
        app.buttons["Вкладки"].tap(); app.buttons["Закрыть вкладку"].tap()
        XCTAssertTrue(app.staticTexts["Wai Browser test"].waitForExistence(timeout: 30))
        app.buttons["Меню"].tap()
        app.buttons["Закладки"].tap()
        XCTAssertTrue(app.buttons["Wai Browser test"].waitForExistence(timeout: 10))
        capture("bookmarks")
        app.buttons["Готово"].tap()
        app.links["Second page"].tap()
        XCTAssertTrue(app.staticTexts["Second test page"].waitForExistence(timeout: 15))
        app.buttons["Назад"].tap()
        XCTAssertTrue(app.staticTexts["Wai Browser test"].waitForExistence(timeout: 15))
        app.links["Download receipt"].tap()
        XCTAssertTrue(app.navigationBars["Загрузки"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["receipt.txt"].exists)
        capture("downloads")
        app.buttons["Готово"].tap()
        app.buttons["Меню"].tap(); app.buttons["История"].tap()
        app.buttons["Очистить"].tap(); app.buttons["Очистить историю"].tap()
        XCTAssertTrue(app.staticTexts["История пуста"].waitForExistence(timeout: 10))
    }

    func testBrowsingAndCertificateSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["Меню"]
        XCTAssertTrue(menu.waitForExistence(timeout: 60))
        app.buttons["Новая вкладка"].tap()
        let tabCount = app.buttons["Вкладки"].value as? String
        let testSite = "wai-ui-" + String(UUID().uuidString.prefix(8)).lowercased() + ".example"
        XCTAssertTrue(app.links["Т-Банк ↗"].waitForExistence(timeout: 60))
        capture("01-home")

        openSettings(in: app)
        XCTAssertTrue(app.navigationBars["Сертификаты"].waitForExistence(timeout: 20))
        let siteSearch = app.searchFields["Найти сайт"]
        siteSearch.tap(); siteSearch.typeText("rzd.ru")
        XCTAssertTrue(app.staticTexts["rzd.ru"].exists)
        capture("02-certificates")
        let site = app.textFields["Адрес сайта или ссылка"]
        site.tap()
        site.typeText("https://www.\(testSite)/page")
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts[testSite].waitForExistence(timeout: 10))
        app.buttons["Готово"].tap()
        let confirmation = app.alerts["Применить настройки?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.buttons["Отмена"].tap()
        XCTAssertTrue(app.navigationBars["Сертификаты"].exists)
        app.buttons["Готово"].tap()
        confirmation.buttons["Применить и обновить"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 20))

        let address = app.searchFields["address"]
        address.tap()
        address.typeText("http://127.0.0.1:9561/\n")
        let download = app.links["Download receipt"]
        XCTAssertTrue(download.waitForExistence(timeout: 60))
        capture("03-browsing")
        app.buttons["Новая вкладка"].tap()
        address.typeText("http://127.0.0.1:9561/\n")
        XCTAssertTrue(download.waitForExistence(timeout: 60))
        app.buttons["Вкладки"].tap()
        XCTAssertTrue(app.buttons["Закрыть вкладку"].waitForExistence(timeout: 10))
        app.buttons["Закрыть вкладку"].tap()
        XCTAssertEqual(app.buttons["Вкладки"].value as? String, tabCount)
        XCTAssertTrue(download.waitForExistence(timeout: 20))
        openSettings(in: app)
        removeSite(testSite, in: app)
        app.buttons["Готово"].tap()
        confirmation.buttons["Применить и обновить"].tap()
        XCTAssertTrue(download.waitForExistence(timeout: 60))
    }

    private func removeSite(_ name: String, in app: XCUIApplication) {
        let search = app.searchFields["Найти сайт"]
        search.tap()
        if let text = search.value as? String { search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count)) }
        search.typeText(name)
        app.staticTexts[name].swipeLeft()
        let delete = app.buttons.matching(NSPredicate(format: "label IN %@", ["Delete", "Удалить"])).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        XCTAssertTrue(app.staticTexts[name].waitForNonExistence(timeout: 5))
        capture("certificate-removed")
    }
    private func openSettings(in app: XCUIApplication) {
        app.buttons["Меню"].tap()
        app.buttons["Сертификаты"].tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
