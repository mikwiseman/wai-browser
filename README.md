# Wai Browser

A native macOS browser based on Chromium/CEF. Russian CA trust is confined to this browser and selected domains. macOS 13+, Apple Silicon.

[Download 0.1.0](https://github.com/mikwiseman/wai-browser/releases/download/v0.1.0/WaiBrowser-0.1.0-3-arm64.zip)

Unzip and move **Wai Browser.app** to Applications. Certificate settings: **WAI → Сертификаты…**. Changes apply after restarting the browser.

Default domains: `rzd.ru`, `tbank.ru`, `tbank-online.com`, `tinkoff.ru`, including subdomains. No certificates are installed into macOS Keychain. Supports RSA HTTPS; GOST/CryptoPro electronic signing is not included.

Signed by WaiWai, LLC and notarized by Apple. Sparkle verifies both the update feed and downloaded releases. This repository contains distribution files; application sources are maintained separately.

Initial release. Public RZD and T-Bank pages were tested; authenticated banking and ticket purchases were not. This is not a complete privacy audit of Chromium.
