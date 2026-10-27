import XCTest

@MainActor final class BrowserUITests: XCTestCase {
    func testBrowsingAndCertificateSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let shield = app.buttons["Сертификаты"]
        XCTAssertTrue(shield.waitForExistence(timeout: 60))
        XCTAssertTrue(app.links["Т-Банк ↗"].waitForExistence(timeout: 60))
        capture("01-home")

        shield.tap()
        XCTAssertTrue(app.navigationBars["Сертификаты"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["rzd.ru"].exists)
        if app.staticTexts["example.org"].exists { removeExampleSite(in: app) }
        capture("02-certificates")
        let site = app.textFields["Адрес сайта или ссылка"]
        site.tap()
        site.typeText("https://www.example.org/page")
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["example.org"].waitForExistence(timeout: 10))
        app.buttons["Готово"].tap()
        let confirmation = app.alerts["Применить настройки?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.buttons["Отмена"].tap()
        XCTAssertTrue(app.navigationBars["Сертификаты"].exists)
        app.buttons["Готово"].tap()
        confirmation.buttons["Применить и обновить"].tap()
        XCTAssertTrue(shield.waitForExistence(timeout: 20))

        let address = app.searchFields["address"]
        address.tap()
        address.typeText("https://waiwai.is/browser\n")
        let download = app.links.matching(NSPredicate(format: "label BEGINSWITH %@", "Скачать для Mac")).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 60))
        capture("03-browsing")
        app.buttons["Новая вкладка"].tap()
        address.typeText("https://waiwai.is/browser\n")
        XCTAssertTrue(download.waitForExistence(timeout: 60))
        app.buttons["Вкладки"].tap()
        XCTAssertTrue(app.buttons["Закрыть вкладку"].waitForExistence(timeout: 10))
        app.buttons["Закрыть вкладку"].tap()
        XCTAssertEqual(app.buttons["Вкладки"].value as? String, "1")
        XCTAssertTrue(download.waitForExistence(timeout: 20))
        shield.tap()
        removeExampleSite(in: app)
        app.buttons["Готово"].tap()
        confirmation.buttons["Применить и обновить"].tap()
        XCTAssertTrue(download.waitForExistence(timeout: 60))
    }

    private func removeExampleSite(in app: XCUIApplication) {
        app.staticTexts["example.org"].swipeLeft()
        let delete = app.buttons.matching(NSPredicate(format: "label IN %@", ["Delete", "Удалить"])).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        XCTAssertFalse(app.staticTexts["example.org"].exists)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
