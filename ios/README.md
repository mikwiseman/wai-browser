# iOS

Native UIKit browser, SwiftUI certificate settings, system WebKit. iOS 26+ is required for the public WebKit storage export/restore API used when revoking certificate trust. Mac Catalyst is enabled for development tests; the distributed Mac app uses Chromium.

## Build

Requires Xcode 26+ and XcodeGen. From the repository root:

```sh
python3 -m pip install -r requirements-dev.txt
python3 tests/ios_fixtures.py
xcodegen generate --spec ios/project.yml
open ios/WaiBrowser.xcodeproj
```

Select an iPhone or iPad simulator and run WaiBrowser. For a physical device, use your signing team and provisioning profile.

## Tests

Start the ephemeral HTTPS fixtures in a separate terminal:

```sh
python3 tests/ios_tls_server.py
```

Run the WaiBrowser scheme's tests on a simulator. Fixture names use `nip.io` to resolve to loopback; DNS must be available. Test keys are generated under ignored `work/ios-certificates/` and never included in the app target or repository.

The same WebKit integration tests can run on Mac Catalyst:

```sh
xcodebuild -project ios/WaiBrowser.xcodeproj -scheme WaiBrowser -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath work/ios-catalyst CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test
```

Catalyst results do not replace an iPhone/iPad interface check.

## Trust

System trust is evaluated first. Additional bundled trust requires a selected domain, valid chain/expiry/hostname and every certificate SAN within the selected scope. IP SANs are rejected. Disabling trust or removing a domain replaces the WebKit data store to discard cached TLS exceptions and open connections. Cookies and localStorage transfer; IndexedDB, service workers and other website storage do not.

The app requests camera or microphone access only when a website uses them. It has no account, analytics SDK, server, system certificate profile or custom cryptography.
