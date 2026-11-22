import Foundation

/// Reads the question name and the A / AAAA addresses from a DNS response.
public enum DNSResponseParser {
    public struct Answer: Equatable {
        public var name: String
        public var addresses: [String]
    }

    public static func parse(_ b: [UInt8]) -> Answer? {
        guard b.count >= 12 else { return nil }
        let flags = Int(b[2]) << 8 | Int(b[3])
        guard flags & 0x8000 != 0 else { return nil } // response bit
        let questions = Int(b[4]) << 8 | Int(b[5])
        let answers = Int(b[6]) << 8 | Int(b[7])
        guard questions >= 1, answers >= 1 else { return nil }

        var offset = 12
        guard let name = readName(b, &offset) else { return nil }
        offset += 4 // QTYPE + QCLASS
        for _ in 1..<questions {
            guard skipName(b, &offset) else { return nil }
            offset += 4
        }

        var addresses: [String] = []
        for _ in 0..<answers {
            guard skipName(b, &offset), offset + 10 <= b.count else { break }
            let type = Int(b[offset]) << 8 | Int(b[offset + 1])
            let length = Int(b[offset + 8]) << 8 | Int(b[offset + 9])
            offset += 10
            guard offset + length <= b.count else { break }
            if type == 1, length == 4 {
                addresses.append(Socks5.Address(host: .ipv4(Array(b[offset..<(offset + 4)])), port: 0).hostString)
            } else if type == 28, length == 16 {
                addresses.append(Socks5.Address(host: .ipv6(Array(b[offset..<(offset + 16)])), port: 0).hostString)
            }
            offset += length
        }
        return addresses.isEmpty ? nil : Answer(name: name, addresses: addresses)
    }

    /// Reads an uncompressed name (question names are never compressed).
    private static func readName(_ b: [UInt8], _ offset: inout Int) -> String? {
        var labels: [String] = []
        while offset < b.count {
            let length = Int(b[offset])
            offset += 1
            if length == 0 { return labels.isEmpty ? nil : labels.joined(separator: ".") }
            guard length < 64, offset + length <= b.count,
                  let label = String(bytes: b[offset..<(offset + length)], encoding: .utf8) else { return nil }
            labels.append(label)
            offset += length
        }
        return nil
    }

    private static func skipName(_ b: [UInt8], _ offset: inout Int) -> Bool {
        while offset < b.count {
            let length = Int(b[offset])
            if length & 0xC0 == 0xC0 { offset += 2; return offset <= b.count } // compression pointer
            offset += 1
            if length == 0 { return true }
            offset += length
        }
        return false
    }
}

/// Remembers which host name each IP address was looked up for, so traffic to that IP can be
/// attributed. Filled from DNS answers that pass through the tunnel and from TLS / HTTP host names.
public final class HostNameCache: @unchecked Sendable {
    private var names: [String: String] = [:]
    private let lock = NSLock()
    private let capacity: Int

    public init(capacity: Int = 20_000) {
        self.capacity = capacity
    }

    public func record(host: String, for address: String) {
        let normalized = DomainNormalizer.normalize(host)
        guard !DomainNormalizer.isIPAddress(normalized) else { return }
        lock.lock()
        if names.count >= capacity { names.removeAll(keepingCapacity: true) }
        names[address] = normalized
        lock.unlock()
    }

    public func record(_ answer: DNSResponseParser.Answer) {
        for address in answer.addresses { record(host: answer.name, for: address) }
    }

    public func name(for address: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return names[address]
    }
}
