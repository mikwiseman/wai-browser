import Foundation
import Security
import WebKit

struct SiteSettings: Codable, Equatable {
    var enabled = true
    var domains = ["rzd.ru", "tbank.ru", "tbank-online.com", "tinkoff.ru"]
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "siteSettings") else { return Self() }
        return (try? JSONDecoder().decode(Self.self, from: data)) ?? Self(enabled: false, domains: [])
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "siteSettings") }
    func allows(_ host: String) -> Bool { enabled && WAIHostMatches(host, domains) }
    static func site(_ input: String) -> String? {
        guard let path = Bundle.main.path(forResource: "public_suffix_list", ofType: "dat") else { return nil }
        return WAISiteFromInput(input, path)
    }
}

final class TrustPolicy {
    var settings: SiteSettings
    let certificates: URL
    init(settings: SiteSettings = .load(), certificates: URL = Bundle.main.resourceURL!.appendingPathComponent("certificates")) {
        self.settings = settings; self.certificates = certificates
    }
    func evaluate(_ trust: SecTrust, host: String) -> SecTrust? {
        guard settings.allows(host),
              let rootData = try? Data(contentsOf: certificates.appendingPathComponent("root.der")),
              let root = SecCertificateCreateWithData(nil, rootData as CFData),
              var chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first, CertificateScope.permits(leaf, settings: settings) else { return nil }
        for name in ["intermediate", "intermediate-2024"] {
            if let data = try? Data(contentsOf: certificates.appendingPathComponent(name+".der")),
               let certificate = SecCertificateCreateWithData(nil, data as CFData) { chain.append(certificate) }
        }
        var scoped: SecTrust?
        guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateSSL(true, host as CFString), &scoped) == errSecSuccess,
              let scoped,
              SecTrustSetAnchorCertificates(scoped, [root] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(scoped, true) == errSecSuccess,
              SecTrustEvaluateWithError(scoped, nil) else { return nil }
        return scoped
    }
    static func systemTrustIsValid(_ trust: SecTrust, host: String) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) else { return false }
        var fresh: SecTrust?
        var policies: CFArray?
        SecTrustCopyPolicies(trust, &policies)
        var checks = (policies as? [SecPolicy]) ?? []
        checks.append(SecPolicyCreateSSL(true, host as CFString))
        guard SecTrustCreateWithCertificates(chain, checks as CFArray, &fresh) == errSecSuccess, let fresh else { return false }
        // A fresh object excludes WebKit's remembered certificate exceptions.
        return SecTrustEvaluateWithError(fresh, nil)
    }
}

struct BrowserProfile: Codable {
    var settings: SiteSettings
    var identifier: UUID
    static func load() -> Self {
        if let data = UserDefaults.standard.data(forKey: "browserProfile"), let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        let value = Self(settings: .load(), identifier: UUID()); value.save(); return value
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "browserProfile") }
    @MainActor static func retireStore(_ identifier: UUID) {
        var retired = UserDefaults.standard.stringArray(forKey: "retiredProfiles") ?? []
        if !retired.contains(identifier.uuidString) { retired.append(identifier.uuidString) }
        UserDefaults.standard.set(retired, forKey: "retiredProfiles")
        cleanRetiredStores()
    }
    @MainActor static func cleanRetiredStores() {
        let active = load().identifier
        for text in UserDefaults.standard.stringArray(forKey: "retiredProfiles") ?? [] {
            guard let id = UUID(uuidString: text), id != active else { continue }
            WKWebsiteDataStore.remove(forIdentifier: id) { error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    let pending = UserDefaults.standard.stringArray(forKey: "retiredProfiles") ?? []
                    UserDefaults.standard.set(pending.filter { $0 != text }, forKey: "retiredProfiles")
                }
            }
        }
    }
}
