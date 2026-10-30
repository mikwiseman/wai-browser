import XCTest
import WebKit
@testable import WaiBrowser

final class TrustTests: XCTestCase {
    func testCatalogMigrationPreservesUserChoices() throws {
        let old = try JSONDecoder().decode(SiteSettings.self, from: Data(#"{"enabled":false,"domains":["rzd.ru","manual.example"]}"#.utf8))
        let updated = old.updatingCatalog()
        XCTAssertFalse(updated.enabled)
        XCTAssertTrue(updated.domains.contains("manual.example"))
        XCTAssertTrue(updated.domains.contains("sberbank.ru"))
        XCTAssertFalse(updated.domains.contains("tbank.ru"))
        XCTAssertEqual(updated.updatingCatalog(), updated)
    }
    let host = "allowed.127.0.0.1.nip.io"
    func fixturePolicy() -> TrustPolicy {
        TrustPolicy(settings: SiteSettings(enabled: true, domains: [host]), certificates: Bundle(for: Self.self).resourceURL!.appendingPathComponent("ios-certificates"))
    }
    func trust(_ name: String) -> SecTrust {
        let path = Bundle(for: Self.self).resourceURL!.appendingPathComponent("ios-certificates/\(name).der")
        let cert = SecCertificateCreateWithData(nil, try! Data(contentsOf: path) as CFData)!
        var result: SecTrust?
        SecTrustCreateWithCertificates([cert] as CFArray, SecPolicyCreateSSL(true, host as CFString), &result)
        return result!
    }
    func testScopedTLS() {
        let policy = fixturePolicy()
        XCTAssertNotNil(policy.evaluate(trust("allowed"), host: host))
        XCTAssertNotNil(policy.evaluate(trust("cdn"), host: "static."+host))
        XCTAssertNil(policy.evaluate(trust("allowed"), host: "wrong."+host))
        XCTAssertNil(policy.evaluate(trust("expired"), host: host))
        XCTAssertNil(policy.evaluate(trust("wrong"), host: host))
        XCTAssertNil(policy.evaluate(trust("outside"), host: "outside.127.0.0.1.nip.io"))
        XCTAssertNil(policy.evaluate(trust("mixed"), host: host), "Every SAN must fit scope: HTTP/2 can reuse an authenticated connection across hosts")
        XCTAssertNil(policy.evaluate(trust("ip-san"), host: host))
        XCTAssertNotNil(policy.evaluate(trust("wildcard"), host: "static."+host))
        policy.settings.enabled = false
        XCTAssertNil(policy.evaluate(trust("allowed"), host: host))
    }
    func testMalformedCertificateNames() {
        for data in [Data(), Data([0x30]), Data([0x30,0x80]), Data([0x30,0x84,0xff,0xff,0xff,0xff]), Data([0x30,0x81,0x01,0]) ] {
            XCTAssertNil(CertificateScope.dnsNames(data))
        }
    }
    @MainActor func testWebKitPageResourcesAndRevocation() async throws {
        let libraryFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: libraryFile) }
        let browser = BrowserController(policy: fixturePolicy(), dataStore: .nonPersistent(), library: BrowserLibrary(file: libraryFile))
        browser.loadViewIfNeeded()
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = browser; window.makeKeyAndVisible()
        let probe = Probe(owner: browser)
        let page = browser.webView
        page.navigationDelegate = probe
        try await probe.load(URL(string: "https://\(host):9543/")!, in: page)
        let loaded = try await page.evaluateJavaScript("document.documentElement.dataset.cdn") as? String
        XCTAssertEqual(loaded, "loaded", "Custom trust must cover cross-origin subresources")
        _ = try await page.evaluateJavaScript("localStorage.setItem('wai-proof','kept'); document.cookie='wai-proof=kept; Secure; SameSite=Lax'")
        for (name,url) in [("outside", "https://outside.127.0.0.1.nip.io:9545/"), ("mismatch", "https://wrong.\(host):9543/"), ("expired", "https://\(host):9544/"), ("wrong root", "https://\(host):9550/")] {
            do { try await probe.load(URL(string: url)!, in: page); XCTFail("Accepted \(name)") }
            catch { XCTAssertTrue([-999,-1012,-1200,-1202,-1201,-1203].contains((error as NSError).code), "\(name): \(error)") }
        }
        var disabled = browser.policy.settings; disabled.enabled = false
        try await browser.applySettings(disabled)
        XCTAssertFalse(browser.tabs.isEmpty)
        let rebuilt = browser.webView; rebuilt.navigationDelegate = probe
        do { try await probe.load(URL(string: "https://\(host):9543/?after-disable")!, in: rebuilt); XCTFail("Trust survived disabling") }
        catch { XCTAssertTrue([-999,-1012,-1200,-1202,-1201,-1203].contains((error as NSError).code)) }
        var enabled = browser.policy.settings; enabled.enabled = true
        try await browser.applySettings(enabled)
        let resumed = browser.webView; resumed.navigationDelegate = probe
        try await probe.load(URL(string: "https://\(host):9543/?enabled")!, in: resumed)
        let persisted = try await resumed.evaluateJavaScript("localStorage.getItem('wai-proof')") as? String
        XCTAssertEqual(persisted,"kept")
        let cookie = try await resumed.evaluateJavaScript("document.cookie") as? String
        XCTAssertTrue(cookie?.contains("wai-proof=kept") == true)
        window.isHidden = true
    }
}

@MainActor final class Probe: NSObject, WKNavigationDelegate {
    let owner: BrowserController
    var continuation: CheckedContinuation<Void, Error>?
    private var expected: WKNavigation?
    init(owner: BrowserController) { self.owner = owner }
    func load(_ url: URL, in page: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; expected = page.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)) }
    }
    func finish(_ error: Error? = nil) { let c=continuation; continuation=nil; if let error { c?.resume(throwing:error) } else { c?.resume() } }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if navigation === expected { finish() } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if navigation === expected { finish(error) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if navigation === expected { finish(error) } }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition,URLCredential?) -> Void) { owner.webView(webView,didReceive:challenge,completionHandler:completionHandler) }
}
