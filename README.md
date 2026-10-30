# Wai Browser

A native browser with additional certificate trust for selected websites.

[Website](https://waiwai.is/browser) · [Download for Mac](https://github.com/mikwiseman/wai-browser/releases/latest) · [Support](https://waiwai.is/browser/support) · [Privacy](https://waiwai.is/browser/privacy)

- **Mac:** Apple Silicon, macOS 13+. CEF 156.0.14 / Chromium 156.0.8078.48, AppKit and Sparkle. Signed and notarized releases.
- **iPhone and iPad:** iOS 26+, UIKit, SwiftUI and WebKit. Available through [TestFlight](https://testflight.apple.com/join/p9BsFGNt).

History, bookmarks, downloads, page search and tabs. Open tabs and the selected tab return after relaunch. On iOS, the menu next to the address opens history, bookmarks, downloads, sharing and certificate settings. History is searchable and can be cleared; bookmarks and downloaded files can be removed individually. Browsing data stays on the device; there is no WAI account or sync.

The Mac engine is the checksum-pinned upstream CEF binary. There is no Electron, bundled extension or WAI analytics SDK. This is not a full audit of Chromium's network services.

## Certificates

Open **WAI → Сертификаты…** on Mac or **Меню → Сертификаты** on iOS. Search the list, add a site by URL or from the current tab, or remove an entry.

Version 0.3.0 bundles 1,386 domain rules from the [Gosuslugi certificate issuance registry](https://www.gosuslugi.ru/api/nsi/v1/custom/dic/tls/csv), including the four previously supported domains. Exact registry scopes are preserved; redundant subdomains are combined only when their parent is already listed. A registry entry does not prove that a site currently serves a Russian certificate. User additions, removals and the disabled switch survive catalog updates.

The [catalog snapshot](resources/certificates/sites.json) records its source, retrieval time, input checksum and excluded public-suffix entries. Update it with `python3 scripts/update_sites.py`; the app itself makes no registry requests.

Additional trust applies only inside Wai Browser. Hostname, expiry and chain checks remain active; every DNS name on the certificate must fit the selected domains. IP certificates are excluded. Certificates already trusted by the operating system retain normal behavior. There is no TLS-error bypass, proxy or system certificate installation.

Mac offers to restart after changes and restores open tab URLs. iOS applies changes by reloading tabs. Revoking trust on iOS creates a fresh WebKit network session and transfers cookies and localStorage; other website storage is not transferred, so some sites may require signing in again. Save unfinished forms before applying changes.

The bundled root and intermediates come from T-Bank's public downloads. Sources and SHA-256 hashes are in [the manifest](resources/certificates/manifest.json). Certificates update with signed app releases. **RSA TLS is supported; GOST, CryptoPro and electronic signatures are not.** Importing arbitrary CA files is not implemented.

Mac profile: `~/Library/Application Support/Wai Browser`. [Certificate-store design](docs/profile-store.md).

## Build for Mac

Requires Xcode command-line tools, CMake, Python 3.12+ and Node.js for integration tests.

```sh
python3 -m pip install -r requirements-dev.txt
WAI_SIGN_IDENTITY=- ./scripts/build.sh
npm ci --ignore-scripts
WAI_SIGN_IDENTITY=- npm run test:browser
```

The build downloads pinned CEF and Sparkle, runs unit checks and signs the app. `-` is an ad-hoc identity for local development; distribution requires your Developer ID identity. Output: `build/Wai Browser.app`.

Browser tests use disposable profiles and TLS fixtures, with a mock Keychain only in test launches. The production app uses normal macOS Keychain encryption. Keep test profiles in the OS temporary directory, outside Documents.

## Build for iOS

See [ios/README.md](ios/README.md) for Xcode, simulator and WebKit test instructions.

## Keyboard

Both versions support Command-L/T/W/R/F, Command-Shift-T, Command-comma, Command-[ / ], Control-Tab and Command-1…9. History: Command-Y; bookmark the page: Command-D; bookmarks: Command-Option-B. Native text editing keeps copy, cut, paste, select all and undo/redo. iOS shortcuts require an external keyboard. Mac also provides downloads (Command-Shift-J), save, print, zoom and Quit in its native menus.

## Releases

Sparkle checks and downloads updates from the [signed HTTPS feed](https://mikwiseman.github.io/wai-browser/appcast.xml). Updates include the engine and certificates. A new upstream engine still needs a tested, signed Wai Browser release.

```sh
python3 scripts/release.py --build-number 5 --feed-url https://mikwiseman.github.io/wai-browser/appcast.xml --download-prefix https://github.com/mikwiseman/wai-browser/releases/download/v0.3.0/
```

The release script builds, tests, signs, notarizes and staples the app, then prepares signed archives, deltas and an appcast. It does not publish. Signing uses 1Password CLI and the local Apple API configuration; private keys are never included in this repository.

[Validation and known limits](QA.md) · [Chromium-Gost review](docs/chromium-gost.md)
