# Chromium-Gost review — 26 October 2026

Examined the macOS arm64 152.0.7977.169 release from [the project](https://github.com/deemru/Chromium-Gost/releases/tag/152.0.7977.169). Archive fingerprint and extension manifests are recorded in `chromium-gost-review.json`.

The downloaded app uses ad-hoc signing, with no Developer ID team. It bundles four extensions for CryptoPro/Gosuslugi integration; Госплагин declares `<all_urls>` host access. These findings do not establish malicious behavior, but the additional extension surface is unnecessary for ordinary RSA HTTPS with the Russian CA.

Wai Browser instead uses the upstream CEF engine and a constrained profile certificate store. It does not include GOST cryptography or electronic-signature plugins. A full source/binary reproducibility or network audit of either engine was not performed.
