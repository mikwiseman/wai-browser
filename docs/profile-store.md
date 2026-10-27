# Scoped Chromium certificate store

Wai Browser seeds its own `Default/ServerCertificate` SQLite database before CEF starts. The schema is Chromium version 1. Metadata uses Chromium's small `CertificateMetadata` protobuf; encoding is local and does not require a protobuf runtime.

The root gets `TRUSTED` (3), DNS constraints for the configured domains and an IP constraint limited to `255.255.255.255/32`. An empty CIDR list would allow all IP SANs. The broadcast address cannot be a TCP/TLS endpoint, so this constraint excludes usable IPv4 and IPv6 endpoints. Tests cover valid IP SANs for 127.0.0.1 and ::1.

Intermediates get `UNSPECIFIED` (1), so they help chain building without becoming trust anchors. Empty or disabled scope removes the managed certificates. Unrelated user certificates remain unchanged. The ownership sidecar is written atomically before committing root rotation. Unknown database versions stop startup rather than leaving a potentially unrestricted old entry in use.

Chromium enforces these constraints on certificate SANs, not just the requested URL. A certificate covering multiple unrelated DNS domains may therefore be rejected unless all its names are permitted. The bundled Russian root is not installed into Keychain. Certificates already trusted by macOS or added manually by the user retain Chromium's normal behavior.

Settings apply on the next start. The live database is never edited while this app owns an active profile. A per-profile advisory lock serializes our startup; Chromium's process singleton handles subsequent launches.

Source definitions for the pinned engine:

- [Database schema](https://chromium.googlesource.com/chromium/src/+/156.0.8078.48/components/server_certificate_database/server_certificate_database.cc)
- [Metadata protobuf](https://chromium.googlesource.com/chromium/src/+/156.0.8078.48/components/server_certificate_database/server_certificate_database.proto)
- [Profile integration](https://chromium.googlesource.com/chromium/src/+/156.0.8078.48/chrome/browser/net/profile_network_context_service.cc)
- [Constraint verification](https://chromium.googlesource.com/chromium/src/+/156.0.8078.48/net/cert/cert_verify_proc_builtin.cc)

These are internal Chromium formats. Every engine update must run the actual-browser fixture tests, including cross-origin scripts, non-allowlisted hosts, IP endpoints, expiration and disable/restart. A CEF certificate-error callback alone did not cover subresources in Chrome runtime and is deliberately absent.
