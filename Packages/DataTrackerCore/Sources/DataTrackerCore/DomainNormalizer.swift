import Foundation

/// Reduces host names to the part that identifies a service, so `r4---sn-abc.googlevideo.com`
/// and `r7---sn-xyz.googlevideo.com` are stored as one row (`googlevideo.com`).
public enum DomainNormalizer {
    /// Second-level public suffixes, so `bbc.co.uk` is kept instead of `co.uk`.
    static let multiPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp",
        "co.il", "org.il", "ac.il", "gov.il", "net.il", "muni.il",
        "co.kr", "or.kr", "co.nz", "org.nz", "co.za", "co.in", "net.in", "org.in",
        "com.br", "net.br", "com.cn", "net.cn", "org.cn", "com.hk", "com.tw", "com.sg",
        "com.mx", "com.ar", "com.tr", "com.ua", "com.pl", "com.my", "com.ph", "com.vn",
        "com.sa", "com.eg", "com.co", "com.pe", "co.id", "co.th"
    ]

    /// Parents whose sub-domains are different services (e.g. `mail.google.com` vs `maps.google.com`).
    static let keepThreeLabels: Set<String> = [
        "apple.com", "icloud.com", "google.com", "googleapis.com", "microsoft.com",
        "live.com", "office.com", "office365.com", "amazon.com", "qq.com", "yahoo.com"
    ]

    public static func normalize(_ host: String) -> String {
        var name = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while name.hasSuffix(".") { name.removeLast() }
        if name.hasPrefix("[") && name.hasSuffix("]") {
            name = String(name.dropFirst().dropLast())
        }
        if name.isEmpty { return "unknown" }
        if isIPAddress(name) { return name }

        let labels = name.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return name }

        let lastTwo = labels.suffix(2).joined(separator: ".")
        var keep = multiPartSuffixes.contains(lastTwo) ? 3 : 2
        let registrable = labels.suffix(keep).joined(separator: ".")
        if keepThreeLabels.contains(registrable) { keep += 1 }
        return labels.suffix(min(keep, labels.count)).joined(separator: ".")
    }

    public static func isIPAddress(_ value: String) -> Bool {
        if value.contains(":") {
            return value.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." || $0 == "%" }
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let n = Int(part), part.count <= 3 else { return false }
            return (0...255).contains(n)
        }
    }
}
