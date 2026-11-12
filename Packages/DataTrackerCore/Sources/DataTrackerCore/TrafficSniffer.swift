import Foundation

/// Finds the host name in the first bytes of a connection that was opened to a bare IP address.
/// Only the TLS ClientHello's server name (SNI) or an HTTP `Host:` header is read; nothing is stored
/// except the resulting host name.
public enum TrafficSniffer {
    public static func hostName(in bytes: [UInt8]) -> String? {
        serverName(fromClientHello: bytes) ?? httpHost(in: bytes)
    }

    public static func serverName(fromClientHello b: [UInt8]) -> String? {
        // TLS record: type 0x16 (handshake), version (2), length (2)
        guard b.count > 5, b[0] == 0x16, b[1] == 0x03 else { return nil }
        var i = 5
        // Handshake: type 0x01 (ClientHello), length (3)
        guard b.count > i + 4, b[i] == 0x01 else { return nil }
        i += 4
        i += 2 + 32 // client version + random
        guard b.count > i else { return nil }
        i += 1 + Int(b[i]) // session id
        guard b.count > i + 1 else { return nil }
        i += 2 + (Int(b[i]) << 8 | Int(b[i + 1])) // cipher suites
        guard b.count > i else { return nil }
        i += 1 + Int(b[i]) // compression methods
        guard b.count > i + 1 else { return nil }
        let extensionsEnd = min(b.count, i + 2 + (Int(b[i]) << 8 | Int(b[i + 1])))
        i += 2
        while i + 4 <= extensionsEnd {
            let type = Int(b[i]) << 8 | Int(b[i + 1])
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            i += 4
            guard i + length <= extensionsEnd else { return nil }
            if type == 0x0000 {
                // server_name: list length (2), then entries of type (1) + length (2) + name
                var j = i + 2
                while j + 3 <= i + length {
                    let nameType = b[j]
                    let nameLength = Int(b[j + 1]) << 8 | Int(b[j + 2])
                    j += 3
                    guard j + nameLength <= i + length else { return nil }
                    if nameType == 0 {
                        return String(bytes: b[j..<(j + nameLength)], encoding: .utf8)
                    }
                    j += nameLength
                }
                return nil
            }
            i += length
        }
        return nil
    }

    public static func httpHost(in bytes: [UInt8]) -> String? {
        let prefix = bytes.prefix(2048)
        guard let text = String(bytes: prefix, encoding: .ascii) ?? String(bytes: prefix, encoding: .utf8) else { return nil }
        let methods = ["GET ", "POST ", "HEAD ", "PUT ", "DELETE ", "OPTIONS ", "PATCH ", "CONNECT "]
        guard methods.contains(where: { text.hasPrefix($0) }) else { return nil }
        for line in text.split(separator: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("host:") {
                var host = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !host.hasPrefix("["), let colon = host.lastIndex(of: ":") {
                    host = String(host[..<colon])
                }
                return host.isEmpty ? nil : host
            }
        }
        return nil
    }
}
