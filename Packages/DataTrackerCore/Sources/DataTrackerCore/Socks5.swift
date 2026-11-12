import Foundation

/// Minimal SOCKS5 protocol support for the on-device proxy that sits behind the packet tunnel.
/// It speaks exactly what hev-socks5-tunnel sends: no-auth greeting, CONNECT, and its
/// "UDP in TCP" command (0x05) where UDP datagrams are framed inside the TCP stream.
public enum Socks5 {
    public enum Command: UInt8, Sendable {
        case connect = 0x01
        case bind = 0x02
        case udpAssociate = 0x03
        case udpInTCP = 0x05
    }

    public enum Reply: UInt8, Sendable {
        case succeeded = 0x00
        case generalFailure = 0x01
        case networkUnreachable = 0x03
        case hostUnreachable = 0x04
        case connectionRefused = 0x05
        case commandNotSupported = 0x07
        case addressTypeNotSupported = 0x08
    }

    public enum Host: Hashable, Sendable {
        case ipv4([UInt8])
        case ipv6([UInt8])
        case domain(String)
    }

    public struct Address: Hashable, Sendable, CustomStringConvertible {
        public var host: Host
        public var port: UInt16

        public init(host: Host, port: UInt16) {
            self.host = host
            self.port = port
        }

        public var hostString: String {
            switch host {
            case .ipv4(let b): return b.map(String.init).joined(separator: ".")
            case .ipv6(let b):
                var groups: [String] = []
                for i in stride(from: 0, to: 16, by: 2) {
                    groups.append(String(UInt16(b[i]) << 8 | UInt16(b[i + 1]), radix: 16))
                }
                return groups.joined(separator: ":")
            case .domain(let name): return name
            }
        }

        public var isDomain: Bool {
            if case .domain = host { return true }
            return false
        }

        public var description: String { "\(hostString):\(port)" }

        /// ATYP + address + port, as used in requests, replies and UDP frames.
        public var encoded: [UInt8] {
            var out: [UInt8] = []
            switch host {
            case .ipv4(let b):
                out.append(0x01)
                out.append(contentsOf: b)
            case .ipv6(let b):
                out.append(0x04)
                out.append(contentsOf: b)
            case .domain(let name):
                let bytes = Array(name.utf8.prefix(255))
                out.append(0x03)
                out.append(UInt8(bytes.count))
                out.append(contentsOf: bytes)
            }
            out.append(UInt8(port >> 8))
            out.append(UInt8(port & 0xFF))
            return out
        }
    }

    public enum Parse<T> {
        case needMoreData
        case invalid
        case parsed(T, consumed: Int)
    }

    public struct Request {
        public var command: UInt8
        public var address: Address
    }

    /// `05 NMETHODS METHODS...`. Returns the offered methods.
    public static func parseGreeting(_ bytes: [UInt8]) -> Parse<[UInt8]> {
        guard bytes.count >= 2 else { return .needMoreData }
        guard bytes[0] == 0x05 else { return .invalid }
        let count = Int(bytes[1])
        guard bytes.count >= 2 + count else { return .needMoreData }
        return .parsed(Array(bytes[2..<(2 + count)]), consumed: 2 + count)
    }

    /// Server's answer to the greeting: version 5, "no authentication".
    public static let greetingReply: [UInt8] = [0x05, 0x00]
    public static let greetingRejected: [UInt8] = [0x05, 0xFF]

    /// `05 CMD 00 ATYP ADDR PORT`.
    public static func parseRequest(_ bytes: [UInt8]) -> Parse<Request> {
        guard bytes.count >= 4 else { return .needMoreData }
        guard bytes[0] == 0x05 else { return .invalid }
        switch parseAddress(bytes, at: 3) {
        case .needMoreData: return .needMoreData
        case .invalid: return .invalid
        case .parsed(let address, let consumed):
            return .parsed(Request(command: bytes[1], address: address), consumed: 3 + consumed)
        }
    }

    public static func parseAddress(_ bytes: [UInt8], at offset: Int) -> Parse<Address> {
        guard bytes.count > offset else { return .needMoreData }
        let type = bytes[offset]
        var cursor = offset + 1
        let host: Host
        switch type {
        case 0x01:
            guard bytes.count >= cursor + 4 + 2 else { return .needMoreData }
            host = .ipv4(Array(bytes[cursor..<(cursor + 4)]))
            cursor += 4
        case 0x04:
            guard bytes.count >= cursor + 16 + 2 else { return .needMoreData }
            host = .ipv6(Array(bytes[cursor..<(cursor + 16)]))
            cursor += 16
        case 0x03:
            guard bytes.count > cursor else { return .needMoreData }
            let length = Int(bytes[cursor])
            cursor += 1
            guard bytes.count >= cursor + length + 2 else { return .needMoreData }
            guard length > 0, let name = String(bytes: bytes[cursor..<(cursor + length)], encoding: .utf8) else {
                return .invalid
            }
            host = .domain(name)
            cursor += length
        default:
            return .invalid
        }
        let port = UInt16(bytes[cursor]) << 8 | UInt16(bytes[cursor + 1])
        cursor += 2
        return .parsed(Address(host: host, port: port), consumed: cursor - offset)
    }

    /// `05 REP 00 01 0.0.0.0:0`.
    public static func reply(_ reply: Reply) -> [UInt8] {
        [0x05, reply.rawValue, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
    }

    /// One "UDP in TCP" frame: `DATLEN(2) HDRLEN(1) ADDR PAYLOAD`, where HDRLEN = 3 + len(ADDR).
    public struct UDPFrame: Equatable {
        public var address: Address
        public var payload: [UInt8]

        public init(address: Address, payload: [UInt8]) {
            self.address = address
            self.payload = payload
        }
    }

    /// Parses one frame starting at `offset`. `consumed` is relative to `offset`.
    public static func parseUDPFrame(_ bytes: [UInt8], at offset: Int = 0) -> Parse<UDPFrame> {
        let available = bytes.count - offset
        guard available >= 3 else { return .needMoreData }
        let dataLength = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        let headerLength = Int(bytes[offset + 2])
        guard headerLength >= 5 else { return .invalid }
        guard available >= headerLength + dataLength else { return .needMoreData }
        switch parseAddress(bytes, at: offset + 3) {
        case .needMoreData, .invalid:
            return .invalid
        case .parsed(let address, let consumed):
            guard 3 + consumed == headerLength else { return .invalid }
            let start = offset + headerLength
            let payload = Array(bytes[start..<(start + dataLength)])
            return .parsed(UDPFrame(address: address, payload: payload), consumed: headerLength + dataLength)
        }
    }

    public static func encodeUDPFrame(_ frame: UDPFrame) -> [UInt8] {
        let address = frame.address.encoded
        let length = min(frame.payload.count, Int(UInt16.max))
        var out: [UInt8] = [UInt8(length >> 8), UInt8(length & 0xFF), UInt8(3 + address.count)]
        out.reserveCapacity(3 + address.count + length)
        out.append(contentsOf: address)
        out.append(contentsOf: frame.payload.prefix(length))
        return out
    }
}
