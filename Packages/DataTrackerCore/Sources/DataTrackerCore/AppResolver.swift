import Foundation

/// What a group of traffic is shown as in the app list.
public enum EntryID: Hashable, Sendable {
    /// A built-in app (`AppCatalog`).
    case app(String)
    /// An app the user created by assigning domains to a name.
    case custom(String)
    /// A domain not matched to any app.
    case domain(String)
    /// Traffic to raw IP addresses with no host name.
    case unidentified
    /// Devices connected to this iPhone's Personal Hotspot.
    case hotspot
    /// Traffic from times the tracking VPN was off.
    case untracked

    /// Stable string form, used for navigation and storage.
    public var key: String {
        switch self {
        case .app(let id): return "app:\(id)"
        case .custom(let name): return "custom:\(name)"
        case .domain(let domain): return "domain:\(domain)"
        case .unidentified: return "special:unidentified"
        case .hotspot: return "special:hotspot"
        case .untracked: return "special:untracked"
        }
    }

    public init?(key: String) {
        if key.hasPrefix("app:") { self = .app(String(key.dropFirst(4))); return }
        if key.hasPrefix("custom:") { self = .custom(String(key.dropFirst(7))); return }
        if key.hasPrefix("domain:") { self = .domain(String(key.dropFirst(7))); return }
        switch key {
        case "special:unidentified": self = .unidentified
        case "special:hotspot": self = .hotspot
        case "special:untracked": self = .untracked
        default: return nil
        }
    }
}

/// Display information for an entry.
public struct EntryInfo: Hashable, Sendable {
    public var name: String
    public var symbol: String
    public var colorHex: String
    public var subtitle: String?

    public init(name: String, symbol: String, colorHex: String, subtitle: String? = nil) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.subtitle = subtitle
    }
}

/// Turns stored domains into apps, using the user's assignments first and the built-in catalog second.
public struct AppResolver: Sendable {
    /// Domain → target, where target is an `EntryID.key` of `.app` or `.custom`.
    public private(set) var customMappings: [String: String]
    private let catalogIndex: [String: String]

    public init(catalog: [AppDefinition] = AppCatalog.all, customMappings: [String: String] = [:]) {
        var index: [String: String] = [:]
        for app in catalog {
            for domain in app.domains { index[domain.lowercased()] = app.id }
        }
        self.catalogIndex = index
        self.customMappings = customMappings
    }

    public func resolve(domain: String) -> EntryID {
        if DomainNormalizer.isIPAddress(domain) || domain == "unknown" {
            if let target = customMappings[domain], let id = EntryID(key: target) { return id }
            return .unidentified
        }
        // Walk from the full name towards the registrable part; most specific rule wins.
        var candidate = Substring(domain)
        while true {
            if let target = customMappings[String(candidate)], let id = EntryID(key: target) { return id }
            if let appID = catalogIndex[String(candidate)] { return .app(appID) }
            guard let dot = candidate.firstIndex(of: ".") else { break }
            candidate = candidate[candidate.index(after: dot)...]
            if !candidate.contains(".") { break }
        }
        return .domain(domain)
    }

    public static func info(for id: EntryID) -> EntryInfo {
        switch id {
        case .app(let appID):
            if let app = AppCatalog.byID[appID] {
                return EntryInfo(name: app.name, symbol: app.category.symbol, colorHex: app.category.colorHex)
            }
            return EntryInfo(name: appID, symbol: AppCategory.other.symbol, colorHex: AppCategory.other.colorHex)
        case .custom(let name):
            return EntryInfo(name: name, symbol: "app.badge.fill", colorHex: "0D74CE", subtitle: "Your app")
        case .domain(let domain):
            return EntryInfo(name: domain, symbol: "globe", colorHex: AppCategory.other.colorHex, subtitle: "Not assigned to an app")
        case .unidentified:
            return EntryInfo(name: "Unidentified (IP only)", symbol: "questionmark.circle.fill", colorHex: "8B8D98",
                             subtitle: "Connections without a host name")
        case .hotspot:
            return EntryInfo(name: "Personal Hotspot", symbol: "personalhotspot", colorHex: "30A46C",
                             subtitle: "Devices connected to this iPhone")
        case .untracked:
            return EntryInfo(name: "Not tracked", symbol: "eye.slash.fill", colorHex: "B4B4B4",
                             subtitle: "While per-app tracking was off")
        }
    }
}
