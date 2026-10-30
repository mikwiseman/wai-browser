# Validation — 27 October 2026

- Upstream CEF 156.0.14 / Chromium 156.0.8078.48, archive SHA-256 pinned.
- 24 profile-store checks passed: default domains, normalization, constraints, root/intermediate roles, disable/empty scope, preservation of unrelated certificates and rejection of unknown schema versions.
- 10 actual-browser checks passed: allowed page and cross-origin script; rejection of outside domain, hostname mismatch, expired certificate, unrelated CA, suffix deception, IPv4 and IPv6 SANs; disable/restart; cookies and localStorage persisted across restarts.
- Chromium sandbox enabled. No `--no-sandbox`, `ignore-certificate-errors`, system CA installation or proxy.
- Developer ID: WaiWai, LLC (R4A779QVVY). Nested code signature verified.
- Apple notarization accepted; ticket stapled; Gatekeeper reports `Notarized Developer ID`.
- Native start page and settings rendered and inspected. Certificate settings save correctly; applying them requires restarting the browser.
- Sparkle signing seed stored in 1Password Development and independently read-back verified; local seed removed.

Build 2 loaded RZD (19 stylesheets) and T-Bank (26 stylesheets), including fonts, with no certificate failures for their allowed domains. Pages were visually inspected. Requests to `hdrc.yandex.net` and `mdd.yandex.net` remained blocked by the domain policy. T-Bank also reported site-level DNS/CORS/CSP/ORB errors on auxiliary requests; authenticated workflows remain untested. A normal public HTTPS control page loaded without errors.

Sparkle installed build 2 over a disposable copy of build 1 and relaunched it. The test used a signed loopback feed and the actual release archive. A test-only Info.plist override caused a fallback from delta to full archive. After installation, nested signatures were valid, the production HTTPS feed was restored and the test-only local-network exception was absent. The relaunched UI was inspected. Automatic checks/downloads are configured; the daily scheduler was not waited out.

Build 3 adds the native Quit menu item. The item was visible, Command-Q exited the browser and the profile lock was released. All profile and browser fixture checks passed again. The browser engine and certificate implementation are unchanged from the live-site check.

Published on 27 October 2026: the Pages deployment passed, the live HTTPS feed matched the signed local bytes, and every uploaded asset digest matched. An unmodified notarized build 2 installed build 3 from this public feed and relaunched. Its nested signatures and app/certificate files matched the installed release. The native UI was inspected after relaunch. No authenticated banking, ticket purchase, passkey or DRM flow has been tested. Launch speed and memory have not been benchmarked against other browsers.


## Version 0.2.0, build 4

- 24 profile checks, 21 site-input checks and 10 Chromium TLS integration cases passed.
- Native Mac UI verified: URL/current-site addition, domain normalization, close/Escape/Command-W, Restart/Later, two-tab restoration, Command-L/T/W/comma/1 and undo/redo. An unsaved form prompts before restart; choosing Stay preserves its text.
- Native-field paste is verified. The UI automation tool restores the clipboard before Chromium's asynchronous webpage paste finishes; webpage clipboard shortcuts need a separate manual check.
- The public Sparkle feed installed build 4 over a disposable build 3. Updated code passed nested signature and Gatekeeper checks. Relaunch into the disposable path was not proven while another copy with the same bundle ID was running. A separate launch of the updated copy and its UI were verified.
- iOS archived and exported with Apple Distribution signing. Three tests passed on Mac Catalyst: scoped TLS, malformed SAN parsing, and real WebKit pages/subresources plus revocation and cookie/localStorage preservation.
- Catalyst UI verified: Command-T/W/comma, Escape, address entry and public HTTPS navigation. Command-T's conflict with the system font menu was corrected.
- iPhone/iPad verification is pending: CoreSimulator's launch service failed to boot the isolated test device. App Store screenshots and review submission are not complete.

[UI evidence](docs/ux-qa.json).

## Version 0.3.0, build 5 — 30 October 2026

- 24 profile-store checks, 25 domain/migration checks and three catalog-parser tests passed. The official registry snapshot has 4,883 rows and produces 1,386 domain rules after normalization/deduplication and the four existing defaults. Two public-suffix rows (`mil.ru`, `*.mil.ru`) were excluded. This is an issuance list, not a live compatibility test of every site.
- 13 Chromium integration cases passed, including TLS rejection cases, persistent cookies/localStorage/history, and restoring two tabs with either tab selected. Native Mac history, bookmark creation/manager and certificate search were inspected. The public Sber page rendered with the expanded scope. Authenticated banking remains untested.
- Six iPhone simulator unit/integration tests passed: library persistence/URL filtering, catalog migration, scoped TLS, malformed SANs and real WebKit pages/subresources with trust revocation and cookie/localStorage preservation.
- All three iPhone UI scenarios passed: certificate search/add/remove and apply/cancel, history/bookmarks/multiple tabs and active-tab restoration, navigation, clearing history, attachment downloads and live completion in the open download list. Downloaded fixture bytes match the served file. Rendered screenshots were inspected.
- Mac build 5 passed Developer ID verification, Apple notarization, stapling and Gatekeeper. The release archive's Ed25519 signature and byte length were independently checked.

New browsing data stays local. iOS restores tab URLs, not a tab's previous back/forward stack or unfinished forms. Mac restores URLs in one window; window geometry and grouping are not restored. No account sync, GOST, CryptoPro or electronic-signature support was added.
