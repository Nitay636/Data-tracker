import XCTest
@testable import DataTrackerCore

final class ProtocolTests: XCTestCase {
    func testGreeting() {
        guard case .parsed(let methods, let consumed) = Socks5.parseGreeting([5, 1, 0, 9]) else { return XCTFail() }
        XCTAssertEqual(methods, [0])
        XCTAssertEqual(consumed, 3)
        guard case .needMoreData = Socks5.parseGreeting([5, 2, 0]) else { return XCTFail() }
        guard case .invalid = Socks5.parseGreeting([4, 1, 0]) else { return XCTFail() }
    }

    func testConnectRequestWithDomain() {
        let name = Array("example.com".utf8)
        let bytes: [UInt8] = [5, 1, 0, 3, UInt8(name.count)] + name + [0x01, 0xBB] + [42]
        guard case .parsed(let request, let consumed) = Socks5.parseRequest(bytes) else { return XCTFail() }
        XCTAssertEqual(request.command, Socks5.Command.connect.rawValue)
        XCTAssertEqual(request.address, Socks5.Address(host: .domain("example.com"), port: 443))
        XCTAssertEqual(consumed, bytes.count - 1)
    }

    func testConnectRequestWithIPv4AndPartialData() {
        let full: [UInt8] = [5, 1, 0, 1, 8, 8, 4, 4, 0, 53]
        guard case .needMoreData = Socks5.parseRequest(Array(full.prefix(7))) else { return XCTFail() }
        guard case .parsed(let request, _) = Socks5.parseRequest(full) else { return XCTFail() }
        XCTAssertEqual(request.address.hostString, "8.8.4.4")
        XCTAssertEqual(request.address.port, 53)
    }

    func testIPv6HostString() {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x20; bytes[1] = 0x01; bytes[2] = 0x0d; bytes[3] = 0xb8; bytes[15] = 1
        XCTAssertEqual(Socks5.Address(host: .ipv6(bytes), port: 1).hostString, "2001:db8:0:0:0:0:0:1")
    }

    func testUDPFrameRoundTrip() {
        let frame = Socks5.UDPFrame(address: .init(host: .domain("quic.example"), port: 443), payload: [1, 2, 3, 4, 5])
        let encoded = Socks5.encodeUDPFrame(frame)
        guard case .parsed(let decoded, let consumed) = Socks5.parseUDPFrame(encoded + [9, 9]) else { return XCTFail() }
        XCTAssertEqual(decoded, frame)
        XCTAssertEqual(consumed, encoded.count)
        guard case .needMoreData = Socks5.parseUDPFrame(Array(encoded.dropLast())) else { return XCTFail() }
    }

    func testUDPFrameMatchesHevLayout() {
        // DATLEN=2, HDRLEN=3+7, IPv4 1.2.3.4:53, payload AB CD
        let bytes: [UInt8] = [0, 2, 10, 1, 1, 2, 3, 4, 0, 53, 0xAB, 0xCD]
        guard case .parsed(let frame, let consumed) = Socks5.parseUDPFrame(bytes) else { return XCTFail() }
        XCTAssertEqual(frame.address.hostString, "1.2.3.4")
        XCTAssertEqual(frame.payload, [0xAB, 0xCD])
        XCTAssertEqual(consumed, 12)
        XCTAssertEqual(Socks5.encodeUDPFrame(frame), bytes)
    }

    func testSNIExtraction() {
        XCTAssertEqual(TrafficSniffer.serverName(fromClientHello: Self.clientHello(host: "api.example.com")), "api.example.com")
        XCTAssertNil(TrafficSniffer.serverName(fromClientHello: [0x17, 3, 3, 0, 1, 0]))
    }

    func testHTTPHost() {
        let request = Array("GET /a HTTP/1.1\r\nUser-Agent: x\r\nHost: example.org:8080\r\n\r\n".utf8)
        XCTAssertEqual(TrafficSniffer.hostName(in: request), "example.org")
        XCTAssertNil(TrafficSniffer.httpHost(in: Array("hello".utf8)))
    }

    /// Builds a minimal TLS 1.2 ClientHello with a server_name extension.
    static func clientHello(host: String) -> [UInt8] {
        let name = Array(host.utf8)
        let serverNameEntry: [UInt8] = [0] + be16(name.count) + name
        let serverNameList = be16(serverNameEntry.count) + serverNameEntry
        let sniExtension: [UInt8] = [0, 0] + be16(serverNameList.count) + serverNameList
        let otherExtension: [UInt8] = [0x00, 0x0B, 0x00, 0x02, 0x01, 0x00] // ec_point_formats
        let extensions = otherExtension + sniExtension
        var body: [UInt8] = [3, 3] + [UInt8](repeating: 7, count: 32)
        body += [0] // session id
        body += be16(2) + [0x13, 0x01] // cipher suites
        body += [1, 0] // compression
        body += be16(extensions.count) + extensions
        let handshake: [UInt8] = [1] + be24(body.count) + body
        return [0x16, 3, 1] + be16(handshake.count) + handshake
    }

    static func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    static func be24(_ v: Int) -> [UInt8] { [UInt8(v >> 16), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
}

final class UDPFrameOffsetTests: XCTestCase {
    func testParsesConsecutiveFramesWithOffset() {
        let a = Socks5.encodeUDPFrame(.init(address: .init(host: .ipv4([1, 1, 1, 1]), port: 53), payload: [1]))
        let b = Socks5.encodeUDPFrame(.init(address: .init(host: .domain("x.y"), port: 443), payload: [2, 3]))
        let buffer = a + b
        guard case .parsed(let first, let used) = Socks5.parseUDPFrame(buffer, at: 0) else { return XCTFail() }
        guard case .parsed(let second, let used2) = Socks5.parseUDPFrame(buffer, at: used) else { return XCTFail() }
        XCTAssertEqual(first.payload, [1])
        XCTAssertEqual(second.address.hostString, "x.y")
        XCTAssertEqual(used + used2, buffer.count)
        guard case .needMoreData = Socks5.parseUDPFrame(buffer, at: buffer.count) else { return XCTFail() }
    }
}
