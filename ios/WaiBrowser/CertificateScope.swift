import Foundation
import Security

// HTTP/2 may reuse one authenticated connection for another SAN on its certificate.
// Constrain every DNS SAN, just as the macOS Chromium certificate store does.
enum CertificateScope {
    static func permits(_ certificate: SecCertificate, settings: SiteSettings) -> Bool {
        guard let names = dnsNames(SecCertificateCopyData(certificate) as Data), !names.isEmpty else { return false }
        return names.allSatisfy { name in
            let host = name.hasPrefix("*.") ? String(name.dropFirst(2)) : name
            return !host.contains("*") && settings.allows(host)
        }
    }
    static func dnsNames(_ data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard let certificate = nodes(bytes, in: 0..<bytes.count), certificate.count == 1, certificate[0].tag == 0x30,
              let fields = nodes(bytes, in: certificate[0].content), let tbs = fields.first, tbs.tag == 0x30,
              let body = nodes(bytes, in: tbs.content), let extensionWrapper = body.first(where: { $0.tag == 0xa3 }),
              let wrapped = nodes(bytes, in: extensionWrapper.content), wrapped.count == 1, wrapped[0].tag == 0x30,
              let extensions = nodes(bytes, in: wrapped[0].content) else { return nil }
        var names: [String]?
        for ext in extensions {
            guard ext.tag == 0x30, let parts = nodes(bytes, in: ext.content), let oid = parts.first, oid.tag == 0x06 else { return nil }
            guard Array(bytes[oid.content]) == [0x55, 0x1d, 0x11] else { continue }
            guard names == nil, let value = parts.last, value.tag == 0x04,
                  let wrappedNames = nodes(bytes, in: value.content), wrappedNames.count == 1, wrappedNames[0].tag == 0x30,
                  let alternatives = nodes(bytes, in: wrappedNames[0].content) else { return nil }
            names = []
            for alternative in alternatives {
                // IP addresses and non-DNS identities cannot be scoped by the site's domain list.
                guard alternative.tag == 0x82 else { return nil }
                let ascii = bytes[alternative.content]
                guard !ascii.isEmpty, ascii.allSatisfy({ $0 > 0x20 && $0 < 0x7f }),
                      let name = String(bytes: ascii, encoding: .ascii) else { return nil }
                names?.append(name.lowercased())
            }
        }
        return names
    }
    private struct Node { let tag: UInt8; let content: Range<Int> }
    private static func nodes(_ bytes: [UInt8], in range: Range<Int>) -> [Node]? {
        var offset = range.lowerBound; var result: [Node] = []
        while offset < range.upperBound {
            guard offset + 2 <= range.upperBound else { return nil }
            let tag = bytes[offset]; offset += 1
            let first = Int(bytes[offset]); offset += 1
            var length = first
            if first & 0x80 != 0 {
                let count = first & 0x7f
                guard count > 0, count <= 4, offset + count <= range.upperBound, bytes[offset] != 0 else { return nil }
                length = 0
                for _ in 0..<count { length = (length << 8) | Int(bytes[offset]); offset += 1 }
                guard length >= 128 else { return nil }
            }
            guard length <= range.upperBound-offset else { return nil }
            result.append(Node(tag: tag, content: offset..<(offset+length))); offset += length
        }
        return result
    }
}
