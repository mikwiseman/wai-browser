import UIKit
import WebKit
import SwiftUI

final class BrowserController: UIViewController, WKNavigationDelegate, WKUIDelegate, UISearchBarDelegate, WKDownloadDelegate {
    let policy: TrustPolicy
    private(set) var dataStore: WKWebsiteDataStore
    private(set) var tabs: [WKWebView] = []
    private var selected = 0
    private var closedURLs: [URL] = []
    let library: BrowserLibrary
    private var sessionURLs: [ObjectIdentifier: URL] = [:]
    private var restoringSession = false
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var downloadFiles: [ObjectIdentifier: URL] = [:]
    private var downloads: [WKDownload] = []
    private let downloadStore = BrowserDownloads()
    private var downloadsFolder: URL { downloadStore.folder }
    var webView: WKWebView { tabs[selected] }
    private let address = UISearchBar()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var observations: [NSKeyValueObservation] = []
    private let errorView = UIStackView()
    private let errorLabel = UILabel()
    private struct NavigationFailure { let url: URL?; let message: String }
    private var failures: [ObjectIdentifier: NavigationFailure] = [:]
    private var rejectedHosts: [ObjectIdentifier: Set<String>] = [:]
    private var failedURL: URL? { tabs.isEmpty ? nil : failures[ObjectIdentifier(webView)]?.url }
    private var applyingSettings = false
    private var backItem: UIBarButtonItem!
    private var forwardItem: UIBarButtonItem!
    private var reloadItem: UIBarButtonItem!
    private var tabsItem: UIBarButtonItem!

    init(policy: TrustPolicy? = nil, dataStore: WKWebsiteDataStore? = nil, library: BrowserLibrary? = nil) {
        let profile = BrowserProfile.load()
        self.policy = policy ?? TrustPolicy(settings: profile.settings)
        self.dataStore = dataStore ?? WKWebsiteDataStore(forIdentifier: profile.identifier)
        self.library = library ?? BrowserLibrary()
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        address.placeholder = "Поиск или адрес сайта"; address.searchBarStyle = .minimal
        address.autocapitalizationType = .none; address.autocorrectionType = .no
        address.keyboardType = .webSearch; address.returnKeyType = .go; address.delegate = self
        address.searchTextField.accessibilityIdentifier = "address"
        navigationItem.titleView = address
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: browserMenu())
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Меню"
        backItem = item("chevron.backward", "Назад", #selector(back))
        forwardItem = item("chevron.forward", "Вперёд", #selector(forward))
        reloadItem = item("arrow.clockwise", "Обновить", #selector(reload))
        tabsItem = item("square.on.square", "Вкладки", #selector(showTabs))
        toolbarItems = [backItem, .flexibleSpace(), forwardItem, .flexibleSpace(), reloadItem, .flexibleSpace(), tabsItem, .flexibleSpace(), item("plus", "Новая вкладка", #selector(newTab))]
        navigationController?.isToolbarHidden = false
        progress.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(progress)
        NSLayoutConstraint.activate([progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), progress.leadingAnchor.constraint(equalTo: view.leadingAnchor), progress.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        errorView.axis = .vertical; errorView.spacing = 18; errorView.alignment = .center
        errorView.translatesAutoresizingMaskIntoConstraints = false; errorView.isHidden = true
        errorLabel.numberOfLines = 0; errorLabel.textAlignment = .center; errorLabel.font = .preferredFont(forTextStyle: .body)
        errorView.addArrangedSubview(errorLabel)
        let settings = UIButton(type: .system); settings.setTitle("Настройки сертификатов", for: .normal); settings.addTarget(self, action: #selector(showSettings), for: .touchUpInside); errorView.addArrangedSubview(settings)
        view.addSubview(errorView)
        NSLayoutConstraint.activate([errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor), errorView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28), errorView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28)])
        let session = library.session
        restoringSession = true
        if session.urls.isEmpty { addTab() }
        else { for url in session.urls { addTab(url: url) }; selectTab(min(session.selected, tabs.count - 1)) }
        restoringSession = false
        saveSession()
        BrowserProfile.cleanRetiredStores()
    }
    private func item(_ symbol: String, _ title: String, _ action: Selector) -> UIBarButtonItem {
        let button = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
        button.accessibilityLabel = title; return button
    }
    @discardableResult func addTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let config = configuration ?? WKWebViewConfiguration(); if configuration == nil { config.websiteDataStore = dataStore }
        let page = WKWebView(frame: .zero, configuration: config)
        page.navigationDelegate = self; page.uiDelegate = self; page.allowsBackForwardNavigationGestures = true
        page.isFindInteractionEnabled = true
        #if DEBUG
        page.isInspectable = true
        #endif
        if let url { sessionURLs[ObjectIdentifier(page)] = BrowserLibrary.webURL(url) }
        tabs.append(page); selectTab(tabs.count-1)
        if let url { page.load(URLRequest(url: url)) }
        else if configuration == nil { page.loadHTMLString(Self.home, baseURL: nil) }
        return page
    }
    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        for page in tabs { page.removeFromSuperview() }; selected = index
        webView.translatesAutoresizingMaskIntoConstraints = false; view.insertSubview(webView, at: 0)
        NSLayoutConstraint.activate([webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), webView.leadingAnchor.constraint(equalTo: view.leadingAnchor), webView.trailingAnchor.constraint(equalTo: view.trailingAnchor), webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
        observations = [webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _,_ in self?.refreshChrome() }, webView.observe(\.isLoading, options: [.new]) { [weak self] _,_ in self?.refreshChrome() }, webView.observe(\.url, options: [.new]) { [weak self] _,_ in self?.refreshChrome() }]
        refreshChrome(); saveSession()
    }
    private func refreshChrome() {
        guard !tabs.isEmpty else { return }
        if !address.isFirstResponder && !address.searchTextField.isFirstResponder { address.text = failedURL?.absoluteString ?? (webView.url?.scheme == "about" ? "" : webView.url?.absoluteString) }
        let failure = failures[ObjectIdentifier(webView)]
        errorView.isHidden = failure == nil; webView.isHidden = failure != nil
        errorLabel.text = failure?.message
        progress.progress = Float(webView.estimatedProgress); progress.isHidden = !webView.isLoading
        backItem?.isEnabled = webView.canGoBack; forwardItem?.isEnabled = webView.canGoForward
        reloadItem?.image = UIImage(systemName: webView.isLoading ? "xmark" : "arrow.clockwise")
        reloadItem?.accessibilityLabel = webView.isLoading ? "Остановить" : "Обновить"
        tabsItem?.accessibilityValue = String(tabs.count)
        navigationItem.rightBarButtonItem?.menu = browserMenu()
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let candidate = text.contains("://") ? text : "https://"+text
        let url: URL?
        if !text.contains(" "), text.contains("."), let parsed = URL(string: candidate), ["https","http"].contains(parsed.scheme ?? "") { url = parsed }
        else { var parts = URLComponents(string: "https://www.google.com/search")!; parts.queryItems = [URLQueryItem(name: "q", value: text)]; url = parts.url }
        address.resignFirstResponder(); address.searchTextField.resignFirstResponder()
        if let url { load(url) }
    }
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        DispatchQueue.main.async { searchBar.searchTextField.selectAll(nil) }
    }
    func load(_ url: URL) {
        failures.removeValue(forKey: ObjectIdentifier(webView)); refreshChrome()
        webView.load(URLRequest(url: url))
    }
    func saveSession() {
        guard !restoringSession, !applyingSettings, !tabs.isEmpty else { return }
        library.saveSession(tabs.map { sessionURLs[ObjectIdentifier($0)] }, selected: selected)
    }
    @objc func focusAddress() { address.searchTextField.becomeFirstResponder(); address.searchTextField.selectAll(nil) }
    @objc func newTab() { addTab(); focusAddress() }
    @objc func closeTab() {
        if presentedViewController != nil { dismiss(animated: true); return }
        if let url = webView.url, url.scheme != "about" { closedURLs.append(url) }
        failures.removeValue(forKey: ObjectIdentifier(webView)); rejectedHosts.removeValue(forKey: ObjectIdentifier(webView))
        sessionURLs.removeValue(forKey: ObjectIdentifier(webView))
        webView.stopLoading(); webView.removeFromSuperview(); tabs.remove(at: selected)
        if tabs.isEmpty { addTab() } else { selectTab(min(selected, tabs.count-1)) }
    }
    @objc func restoreTab() { if let url = closedURLs.popLast() { addTab(url: url) } }
    @objc func back() { webView.goBack() }
    @objc func forward() { webView.goForward() }
    @objc func reload() { if webView.isLoading { webView.stopLoading() } else if let failedURL { load(failedURL) } else { webView.reload() } }
    @objc func reloadPage() { if let failedURL { load(failedURL) } else { webView.reload() } }
    @objc func hardReload() { webView.reloadFromOrigin() }
    @objc func nextTab() { selectTab((selected+1)%tabs.count) }
    @objc func previousTab() { selectTab((selected+tabs.count-1)%tabs.count) }
    @objc func chooseTab(_ command: UIKeyCommand) { if let n = Int(command.input ?? "") { selectTab(n == 9 ? tabs.count-1 : n-1) } }
    @objc func findInPage() { webView.findInteraction?.presentFindNavigator(showingReplace: false) }
    private func browserMenu() -> UIMenu {
        let url = tabs.isEmpty ? nil : BrowserLibrary.webURL(webView.url)
        let bookmarked = library.isBookmarked(url)
        func action(_ title: String, _ icon: String, _ perform: @escaping () -> Void) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: icon)) { _ in perform() }
        }
        let bookmark = action(bookmarked ? "Убрать закладку" : "В закладки", bookmarked ? "bookmark.fill" : "bookmark") { [weak self] in self?.toggleBookmark() }
        let share = action("Поделиться", "square.and.arrow.up") { [weak self] in self?.sharePage() }
        if url == nil { bookmark.attributes = .disabled; share.attributes = .disabled }
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [action("История", "clock") { [weak self] in self?.showHistory() }, action("Закладки", "book") { [weak self] in self?.showBookmarks() }, action(downloads.isEmpty ? "Загрузки" : "Загрузки · \(downloads.count)", "arrow.down.circle") { [weak self] in self?.showDownloads() }]),
            UIMenu(options: .displayInline, children: [bookmark, share, action("Найти на странице", "doc.text.magnifyingglass") { [weak self] in self?.findInPage() }]),
            action("Сертификаты", "checkmark.shield") { [weak self] in self?.showSettings() }
        ])
    }
    @objc func showHistory() { showLibrary(.history) }
    @objc func showBookmarks() { showLibrary(.bookmarks) }
    private func showLibrary(_ section: LibraryView.Section) {
        guard presentedViewController == nil else { return }
        let sheet = UIHostingController(rootView: LibraryView(library: library, section: section) { [weak self] url in
            self?.dismiss(animated: true) { self?.load(url) }
        })
        present(sheet, animated: true)
    }
    @objc func toggleBookmark() {
        guard let url = webView.url else { return }
        library.setBookmark(url, title: webView.title, saved: !library.isBookmarked(url)); refreshChrome()
    }
    @objc func sharePage() {
        guard let url = BrowserLibrary.webURL(webView.url), presentedViewController == nil else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }
    private func showDownloads() {
        guard presentedViewController == nil else { return }
        downloadStore.refresh(activeCount: downloads.count)
        let sheet = UIHostingController(rootView: DownloadsView(store: downloadStore) { [weak self] url in
            self?.dismiss(animated: true) {
                guard let self else { return }
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem
                self.present(share, animated: true)
            }
        })
        present(sheet, animated: true)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let attachment = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?
            .trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("attachment") == true
        decisionHandler(attachment || !navigationResponse.canShowMIMEType ? .download : .allow)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { beginDownload(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { beginDownload(download) }
    private func beginDownload(_ download: WKDownload) { downloads.append(download); download.delegate = self; downloadStore.refresh(activeCount: downloads.count); refreshChrome() }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard downloads.contains(where: { $0 === download }) else { completionHandler(nil); return }
        do {
            try FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
            let filename = (suggestedFilename as NSString).lastPathComponent
            let base = downloadsFolder.appendingPathComponent(filename.isEmpty || filename == "." || filename == ".." ? "Файл" : filename)
            var destination = base; var number = 1
            while FileManager.default.fileExists(atPath: destination.path) || downloadFiles.values.contains(destination) {
                destination = base.deletingPathExtension().appendingPathExtension("\(number)" + (base.pathExtension.isEmpty ? "" : "." + base.pathExtension)); number += 1
            }
            let temporary = downloadsFolder.appendingPathComponent(".download-" + UUID().uuidString)
            downloadDestinations[ObjectIdentifier(download)] = temporary
            downloadFiles[ObjectIdentifier(download)] = destination
            completionHandler(temporary)
        } catch { completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard downloads.contains(where: { $0 === download }) else { return }
        if let temporary = downloadDestinations[ObjectIdentifier(download)], let destination = downloadFiles[ObjectIdentifier(download)] {
            do { try FileManager.default.moveItem(at: temporary, to: destination) }
            catch { self.download(download, didFailWithError: error, resumeData: nil); return }
        }
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download)); downloadFiles.removeValue(forKey: ObjectIdentifier(download)); downloads.removeAll { $0 === download }; refreshChrome()
        downloadStore.refresh(activeCount: downloads.count)
        if presentedViewController == nil { showDownloads() }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard downloads.contains(where: { $0 === download }) else { return }
        if let partial = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) { try? FileManager.default.removeItem(at: partial) }
        downloadFiles.removeValue(forKey: ObjectIdentifier(download))
        downloads.removeAll { $0 === download }; refreshChrome()
        downloadStore.refresh(activeCount: downloads.count)
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Не удалось загрузить файл", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Готово", style: .default)); present(alert, animated: true)
    }
    @objc func escape() { if presentedViewController != nil { dismiss(animated: true) } else { webView.stopLoading(); view.endEditing(true) } }
    override var keyCommands: [UIKeyCommand]? {
        guard !applyingSettings else { return [] }
        func key(_ title: String, _ input: String, _ action: Selector, _ flags: UIKeyModifierFlags = .command) -> UIKeyCommand {
            let command = UIKeyCommand(title: title, action: action, input: input, modifierFlags: flags); command.wantsPriorityOverSystemBehavior = true; return command
        }
        var commands = [key("Адресная строка", "l", #selector(focusAddress)), key("Новая вкладка", "t", #selector(newTab)), key("Закрыть вкладку", "w", #selector(closeTab)), key("Вернуть вкладку", "t", #selector(restoreTab), [.command,.shift]), key("Обновить", "r", #selector(reloadPage)), key("Обновить без кэша", "r", #selector(hardReload), [.command,.shift]), key("Назад", "[", #selector(back)), key("Вперёд", "]", #selector(forward)), key("Найти", "f", #selector(findInPage)), key("Сертификаты", ",", #selector(showSettings)), key("Следующая вкладка", "\t", #selector(nextTab), .control), key("Предыдущая вкладка", "\t", #selector(previousTab), [.control,.shift]), key("Закрыть", UIKeyCommand.inputEscape, #selector(escape), [])]
        for n in 1...9 { commands.append(key("Вкладка \(n)", String(n), #selector(chooseTab(_:)))) }
        commands += [key("История", "y", #selector(showHistory)), key("Закладки", "b", #selector(showBookmarks), [.command, .alternate]), key("В закладки", "d", #selector(toggleBookmark))]
        return commands
    }
    @objc func showTabs() {
        let list = UIAlertController(title: "Вкладки", message: nil, preferredStyle: .actionSheet)
        for (index, page) in tabs.enumerated() { list.addAction(UIAlertAction(title: (index == selected ? "✓ " : "")+(page.title ?? "Новая вкладка"), style: .default) { [weak self] _ in self?.selectTab(index) }) }
        list.addAction(UIAlertAction(title: "Закрыть вкладку", style: .destructive) { [weak self] _ in self?.closeTab() })
        list.addAction(UIAlertAction(title: "Отмена", style: .cancel)); list.popoverPresentationController?.barButtonItem = tabsItem; present(list, animated: true)
    }
    @objc func showSettings() {
        guard !applyingSettings, presentedViewController == nil else { return }
        let current = failedURL?.host ?? webView.url?.host
        let settings = TrustSettingsView(settings: policy.settings, currentHost: current) { [weak self] updated in
            guard let self else { return }; self.dismiss(animated: true)
            guard updated != self.policy.settings else { return }
            Task {
                do { try await self.applySettings(updated) }
                catch {
                    let alert = UIAlertController(title: "Не удалось применить настройки", message: "Прежние настройки сохранены. Попробуйте ещё раз.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Готово", style: .default)); self.present(alert, animated: true)
                }
            }
        }
        let sheet = UIHostingController(rootView: settings); sheet.isModalInPresentation = true
        sheet.sheetPresentationController?.detents = [.large()]; present(sheet, animated: true)
    }
    @MainActor func applySettings(_ next: SiteSettings) async throws {
        guard !applyingSettings, next != policy.settings else { return }
        applyingSettings = true
        navigationController?.view.isUserInteractionEnabled = false
        defer { applyingSettings = false; navigationController?.view.isUserInteractionEnabled = true; saveSession() }
        let old = policy.settings
        let revokesTrust = old.enabled && !old.domains.isEmpty && (!next.enabled || old.domains.contains { !WAIHostMatches($0, next.domains) })
        if revokesTrust {
            for download in downloads {
                let temporary = downloadDestinations[ObjectIdentifier(download)]
                download.cancel { _ in if let temporary { try? FileManager.default.removeItem(at: temporary) } }
            }
            downloads.removeAll(); downloadDestinations.removeAll(); downloadFiles.removeAll()
            downloadStore.refresh(activeCount: 0)
        }
        let urls = tabs.map { failures[ObjectIdentifier($0)]?.url ?? $0.url }; let active = selected
        let previousStore = dataStore
        // Release pages before exporting storage so their JavaScript cannot keep modifying it.
        observations = []
        for page in tabs { page.stopLoading(); page.removeFromSuperview(); page.navigationDelegate = nil; page.uiDelegate = nil }
        tabs.removeAll(); failures.removeAll(); rejectedHosts.removeAll(); sessionURLs.removeAll()
        func restoreTabs() {
            for url in urls { addTab(url: url?.scheme == "about" ? nil : url) }
            if tabs.isEmpty { addTab() }; selectTab(min(active,tabs.count-1))
        }
        var replacement = previousStore
        do {
            if revokesTrust {
                // A new data store gives WebKit a fresh network session, including TLS connections.
                let cookies: [HTTPCookie] = await withCheckedContinuation { done in previousStore.httpCookieStore.getAllCookies { done.resume(returning: $0) } }
                let storage: Data = try await withCheckedThrowingContinuation { done in
                    previousStore.fetchData(of: [WKWebsiteDataTypeLocalStorage]) { data,error in
                        if let error { done.resume(throwing:error) } else if let data { done.resume(returning:data) } else { done.resume(throwing:URLError(.cannotDecodeContentData)) }
                    }
                }
                replacement = previousStore.isPersistent ? WKWebsiteDataStore(forIdentifier: UUID()) : .nonPersistent()
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void,Error>) in
                    replacement.restoreData(storage) { error in if let error { done.resume(throwing:error) } else { done.resume() } }
                }
                for cookie in cookies { await withCheckedContinuation { done in replacement.httpCookieStore.setCookie(cookie) { done.resume() } } }
            }
        } catch {
            if replacement !== previousStore, let id = replacement.identifier { BrowserProfile.retireStore(id) }
            restoreTabs()
            throw error
        }
        dataStore = replacement; policy.settings = next
        if let identifier = replacement.identifier { BrowserProfile(settings:next,identifier:identifier).save() }
        restoreTabs()
        if revokesTrust, let identifier = previousStore.identifier { BrowserProfile.retireStore(identifier) }
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        evaluateChallenge(challenge, page: webView, completionHandler: completionHandler)
    }
    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        evaluateChallenge(challenge, page: nil, completionHandler: completionHandler)
    }
    private func evaluateChallenge(_ challenge: URLAuthenticationChallenge, page: WKWebView?, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { completionHandler(.performDefaultHandling, nil); return }
        let host = challenge.protectionSpace.host
        // Snapshot settings so a change made while evaluation is pending cannot grant old trust.
        let snapshot = policy.settings
        let evaluator = TrustPolicy(settings: snapshot, certificates: policy.certificates)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let systemValid = TrustPolicy.systemTrustIsValid(trust, host: host)
            let accepted = systemValid ? nil : evaluator.evaluate(trust, host: host)
            DispatchQueue.main.async {
                guard let self, self.policy.settings == snapshot else { completionHandler(.cancelAuthenticationChallenge, nil); return }
                if systemValid { completionHandler(.performDefaultHandling, nil) }
                else if let accepted { completionHandler(.useCredential, URLCredential(trust: accepted)) }
                else {
                    if let page { self.rejectedHosts[ObjectIdentifier(page), default: []].insert(host.lowercased()) }
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard tabs.contains(where: { $0 === webView }) else { return }
        sessionURLs[ObjectIdentifier(webView)] = BrowserLibrary.webURL(webView.url); saveSession()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard tabs.contains(where: { $0 === webView }) else { return }
        if let url = webView.url { library.visit(url, title: webView.title) }
        // WebKit can deliver didFinish before it delivers the page title.
        let url = webView.url
        webView.evaluateJavaScript("document.title") { [weak self, weak webView] title, _ in
            guard webView?.url == url else { return }
            self?.library.updateTitle(title as? String, for: url)
        }
        if webView === self.webView { refreshChrome() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(webView, error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(webView, error) }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failures.removeValue(forKey: ObjectIdentifier(webView)); rejectedHosts.removeValue(forKey: ObjectIdentifier(webView))
        if !tabs.isEmpty, webView === self.webView { refreshChrome() }
    }
    private func showError(_ page: WKWebView, _ error: Error) {
        guard tabs.contains(where: { $0 === page }) else { return }
        let error = error as NSError
        let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? page.url
        let certificateRejected = url?.host.map { rejectedHosts[ObjectIdentifier(page)]?.contains($0.lowercased()) == true } ?? false
        guard error.code != NSURLErrorCancelled || certificateRejected else { return }
        let message = certificateRejected ? "Не удалось проверить сертификат сайта.\nПроверьте адрес и настройки доверия." : "Не удалось открыть сайт.\n"+error.localizedDescription
        failures[ObjectIdentifier(page)] = NavigationFailure(url: url, message: message)
        if page === webView { refreshChrome() }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { addTab(configuration: configuration) }
    static let home = """
    <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>:root{color-scheme:light dark}body{margin:0;font:18px -apple-system;background:light-dark(#f5f5ed,#20251e);color:light-dark(#20251e,#f5f5ed)}main{padding:20vh 9vw 5vh}h1{font-size:120px;letter-spacing:-12px;font-weight:850;margin:0}p{font-size:22px;line-height:1.35;margin:22px 0 48px}a{color:inherit;text-decoration:none;border-bottom:1px solid #888;padding-bottom:8px;margin-right:26px}footer{font-size:13px;opacity:.6;margin-top:72px;line-height:1.5}</style><main><h1>wai.</h1><p>Весь интернет.<br>С вашим доверием.</p><a href="https://www.rzd.ru">РЖД ↗</a><a href="https://www.tbank.ru">Т-Банк ↗</a><footer>Сертификаты для выбранных сайтов —<br>в меню браузера.</footer></main>
    """
}
