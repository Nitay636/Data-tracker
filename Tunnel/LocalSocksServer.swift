import Foundation
import Network
import DataTrackerCore

/// Called for every chunk relayed. `label` is the normalized domain (or IP), `received` is
/// download (internet → iPhone) and `sent` is upload.
typealias TrafficReporter = (_ label: String, _ kind: NetworkKind, _ received: Int, _ sent: Int) -> Void

private protocol Relay: AnyObject {
    func cancel()
}

/// SOCKS5 server on 127.0.0.1 inside the tunnel extension. hev-socks5-tunnel turns the packets
/// apps send into SOCKS5 connections to this server; it opens the real connections to the internet
/// and counts the bytes in each direction.
///
/// Connections opened by a packet tunnel provider never go through its own tunnel, so there is no loop.
final class LocalSocksServer {
    enum ServerError: Error { case noFreePort }

    static let candidatePorts: [UInt16] = [17_891, 27_891, 37_891, 47_891, 57_891]

    private let queue = DispatchQueue(label: "datatracker.socks", qos: .userInitiated)
    private let report: TrafficReporter
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: SocksSession] = [:]

    init(report: @escaping TrafficReporter) {
        self.report = report
    }

    func start(completion: @escaping (Result<UInt16, Error>) -> Void) {
        queue.async { self.listen(candidate: 0, completion: completion) }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            let open = Array(self.sessions.values)
            self.sessions.removeAll()
            open.forEach { $0.close() }
        }
    }

    private func listen(candidate: Int, completion: @escaping (Result<UInt16, Error>) -> Void) {
        guard candidate < Self.candidatePorts.count else {
            completion(.failure(ServerError.noFreePort))
            return
        }
        let port = Self.candidatePorts[candidate]
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            listen(candidate: candidate + 1, completion: completion)
            return
        }

        var settled = false
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, !settled else { return }
            switch state {
            case .ready:
                settled = true
                self.listener = listener
                completion(.success(port))
            case .failed:
                settled = true
                listener.cancel()
                self.listen(candidate: candidate + 1, completion: completion)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        let session = SocksSession(client: connection, queue: queue, report: report)
        let id = ObjectIdentifier(session)
        sessions[id] = session
        session.onClose = { [weak self] in
            self?.sessions[id] = nil
        }
        session.start()
    }
}

// MARK: - Session (handshake)

private final class SocksSession {
    private enum Phase { case greeting, request, relaying }

    let client: NWConnection
    let queue: DispatchQueue
    let report: TrafficReporter
    var onClose: (() -> Void)?

    private var phase = Phase.greeting
    private var buffer: [UInt8] = []
    private var relay: Relay?
    private var closed = false

    init(client: NWConnection, queue: DispatchQueue, report: @escaping TrafficReporter) {
        self.client = client
        self.queue = queue
        self.report = report
    }

    func start() {
        client.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        client.start(queue: queue)
        receiveHandshake()
    }

    func close() {
        guard !closed else { return }
        closed = true
        relay?.cancel()
        relay = nil
        client.cancel()
        let callback = onClose
        onClose = nil
        callback?()
    }

    private func receiveHandshake() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty { self.buffer.append(contentsOf: data) }
            if error != nil || isComplete {
                self.close()
                return
            }
            self.processHandshake()
        }
    }

    private func send(_ bytes: [UInt8], then: (() -> Void)? = nil) {
        client.send(content: Data(bytes), completion: .contentProcessed { _ in then?() })
    }

    private func processHandshake() {
        if phase == .greeting {
            switch Socks5.parseGreeting(buffer) {
            case .needMoreData:
                receiveHandshake()
                return
            case .invalid:
                close()
                return
            case .parsed(let methods, let consumed):
                buffer.removeFirst(consumed)
                guard methods.contains(0x00) else {
                    send(Socks5.greetingRejected) { [weak self] in self?.close() }
                    return
                }
                send(Socks5.greetingReply)
                phase = .request
            }
        }

        guard phase == .request else { return }
        switch Socks5.parseRequest(buffer) {
        case .needMoreData:
            receiveHandshake()
        case .invalid:
            close()
        case .parsed(let request, let consumed):
            buffer.removeFirst(consumed)
            let leftover = buffer
            buffer = []
            phase = .relaying
            let finish: () -> Void = { [weak self] in self?.close() }

            switch Socks5.Command(rawValue: request.command) {
            case .connect:
                let tcp = TCPRelay(client: client, target: request.address, queue: queue, report: report, onFinish: finish)
                relay = tcp
                tcp.start(leftover: leftover)
            case .udpInTCP:
                send(Socks5.reply(.succeeded))
                let udp = UDPRelay(client: client, queue: queue, report: report, onFinish: finish)
                relay = udp
                udp.start(leftover: leftover)
            default:
                send(Socks5.reply(.commandNotSupported)) { [weak self] in self?.close() }
            }
        }
    }
}

// MARK: - Helpers

private enum Endpoints {
    static func host(for address: Socks5.Address) -> NWEndpoint.Host {
        switch address.host {
        case .ipv4(let bytes):
            if let ip = IPv4Address(Data(bytes)) { return .ipv4(ip) }
        case .ipv6(let bytes):
            if let ip = IPv6Address(Data(bytes)) { return .ipv6(ip) }
        case .domain(let name):
            return .name(name, nil)
        }
        return .name(address.hostString, nil)
    }

    static func port(for address: Socks5.Address) -> NWEndpoint.Port {
        NWEndpoint.Port(rawValue: address.port) ?? .any
    }

    static func kind(of path: NWPath?) -> NetworkKind? {
        guard let path else { return nil }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { return .wifi }
        return nil
    }

    static func label(for address: Socks5.Address) -> String {
        address.isDomain ? DomainNormalizer.normalize(address.hostString) : address.hostString
    }
}

// MARK: - TCP

private final class TCPRelay: Relay {
    private let client: NWConnection
    private let target: Socks5.Address
    private let queue: DispatchQueue
    private let report: TrafficReporter
    private let onFinish: () -> Void

    private var remote: NWConnection?
    private var label: String
    private var needsSniffing: Bool
    private var kind = NetworkKind.wifi
    private var replied = false
    private var finished = false
    private var clientDone = false
    private var remoteDone = false

    init(client: NWConnection, target: Socks5.Address, queue: DispatchQueue,
         report: @escaping TrafficReporter, onFinish: @escaping () -> Void) {
        self.client = client
        self.target = target
        self.queue = queue
        self.report = report
        self.onFinish = onFinish
        self.label = Endpoints.label(for: target)
        self.needsSniffing = !target.isDomain
    }

    func start(leftover: [UInt8]) {
        let remote = NWConnection(host: Endpoints.host(for: target), port: Endpoints.port(for: target), using: .tcp)
        self.remote = remote
        remote.stateUpdateHandler = { [weak self, weak remote] state in
            guard let self, !self.finished else { return }
            switch state {
            case .ready:
                if let kind = Endpoints.kind(of: remote?.currentPath) { self.kind = kind }
                guard !self.replied else { return }
                self.replied = true
                self.client.send(content: Data(Socks5.reply(.succeeded)), completion: .contentProcessed { _ in })
                if leftover.isEmpty {
                    self.readClient()
                } else {
                    self.forwardToRemote(Data(leftover), isComplete: false)
                }
                self.readRemote()
            case .failed:
                self.fail()
            default:
                break
            }
        }
        remote.pathUpdateHandler = { [weak self] path in
            if let kind = Endpoints.kind(of: path) { self?.kind = kind }
        }
        remote.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, !self.replied, !self.finished else { return }
            self.fail()
        }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        remote?.cancel()
        remote = nil
    }

    private func finish() {
        guard !finished else { return }
        cancel()
        onFinish()
    }

    private func fail() {
        guard !replied else {
            finish()
            return
        }
        replied = true
        client.send(content: Data(Socks5.reply(.hostUnreachable)), completion: .contentProcessed { [weak self] _ in
            self?.finish()
        })
    }

    // Client → internet (upload)
    private func readClient() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty {
                self.forwardToRemote(data, isComplete: isComplete)
            } else if isComplete {
                self.closeUpload()
            } else if error != nil {
                self.finish()
            } else {
                self.readClient()
            }
        }
    }

    private func forwardToRemote(_ data: Data, isComplete: Bool) {
        if needsSniffing {
            needsSniffing = false
            if let host = TrafficSniffer.hostName(in: [UInt8](data.prefix(4096))) {
                label = DomainNormalizer.normalize(host)
            }
        }
        remote?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.finished else { return }
            if error != nil {
                self.finish()
                return
            }
            self.report(self.label, self.kind, 0, data.count)
            if isComplete { self.closeUpload() } else { self.readClient() }
        })
    }

    private func closeUpload() {
        clientDone = true
        remote?.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
        if remoteDone { finish() }
    }

    // Internet → client (download)
    private func readRemote() {
        remote?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty {
                self.client.send(content: data, completion: .contentProcessed { [weak self] error in
                    guard let self, !self.finished else { return }
                    if error != nil {
                        self.finish()
                        return
                    }
                    self.report(self.label, self.kind, data.count, 0)
                    if isComplete { self.closeDownload() } else { self.readRemote() }
                })
            } else if isComplete {
                self.closeDownload()
            } else if error != nil {
                self.finish()
            } else {
                self.readRemote()
            }
        }
    }

    private func closeDownload() {
        remoteDone = true
        client.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
        if clientDone { finish() }
    }
}

// MARK: - UDP (framed inside the TCP connection from hev-socks5-tunnel)

private final class UDPRelay: Relay {
    private static let maximumFlows = 64

    private let client: NWConnection
    private let queue: DispatchQueue
    private let report: TrafficReporter
    private let onFinish: () -> Void

    private var buffer: [UInt8] = []
    private var flows: [Socks5.Address: UDPFlow] = [:]
    private var flowOrder: [Socks5.Address] = []
    private var finished = false

    init(client: NWConnection, queue: DispatchQueue, report: @escaping TrafficReporter, onFinish: @escaping () -> Void) {
        self.client = client
        self.queue = queue
        self.report = report
        self.onFinish = onFinish
    }

    func start(leftover: [UInt8]) {
        buffer = leftover
        processFrames()
        readClient()
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        flows.values.forEach { $0.cancel() }
        flows.removeAll()
        flowOrder.removeAll()
    }

    private func finish() {
        guard !finished else { return }
        cancel()
        onFinish()
    }

    private func readClient() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty {
                self.buffer.append(contentsOf: data)
                self.processFrames()
            }
            if isComplete || error != nil {
                self.finish()
                return
            }
            if !self.finished { self.readClient() }
        }
    }

    private func processFrames() {
        var offset = 0
        parsing: while !finished {
            switch Socks5.parseUDPFrame(buffer, at: offset) {
            case .needMoreData:
                break parsing
            case .invalid:
                finish()
                return
            case .parsed(let frame, let consumed):
                offset += consumed
                flow(for: frame.address).send(frame.payload)
            }
        }
        if offset > 0 { buffer.removeFirst(min(offset, buffer.count)) }
    }

    private func flow(for address: Socks5.Address) -> UDPFlow {
        if let existing = flows[address] { return existing }
        if flowOrder.count >= Self.maximumFlows {
            let oldest = flowOrder.removeFirst()
            flows.removeValue(forKey: oldest)?.cancel()
        }
        // For domain destinations hev-socks5-tunnel substitutes the original address itself.
        let replyAddress = address.isDomain ? Socks5.Address(host: .ipv4([0, 0, 0, 0]), port: address.port) : address
        let flow = UDPFlow(address: address, queue: queue, label: Endpoints.label(for: address), report: report) { [weak self] payload in
            guard let self, !self.finished else { return }
            let frame = Socks5.encodeUDPFrame(Socks5.UDPFrame(address: replyAddress, payload: payload))
            self.client.send(content: Data(frame), completion: .contentProcessed { [weak self] error in
                if error != nil { self?.finish() }
            })
        }
        flows[address] = flow
        flowOrder.append(address)
        flow.start()
        return flow
    }
}

private final class UDPFlow {
    private let connection: NWConnection
    private let label: String
    private let report: TrafficReporter
    private let onDatagram: ([UInt8]) -> Void
    private var kind = NetworkKind.wifi
    private var cancelled = false

    init(address: Socks5.Address, queue: DispatchQueue, label: String, report: @escaping TrafficReporter,
         onDatagram: @escaping ([UInt8]) -> Void) {
        self.connection = NWConnection(host: Endpoints.host(for: address), port: Endpoints.port(for: address), using: .udp)
        self.label = label
        self.report = report
        self.onDatagram = onDatagram
        self.queue = queue
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let kind = Endpoints.kind(of: self.connection.currentPath) { self.kind = kind }
            case .failed:
                self.cancel()
            default:
                break
            }
        }
        connection.pathUpdateHandler = { [weak self] path in
            if let kind = Endpoints.kind(of: path) { self?.kind = kind }
        }
    }

    private let queue: DispatchQueue

    func start() {
        connection.start(queue: queue)
        receive()
    }

    func send(_ payload: [UInt8]) {
        guard !cancelled else { return }
        let size = payload.count
        connection.send(content: Data(payload), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { return }
            self.report(self.label, self.kind, 0, size)
        })
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        connection.cancel()
    }

    private func receive() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, !self.cancelled else { return }
            if let data, !data.isEmpty {
                self.report(self.label, self.kind, data.count, 0)
                self.onDatagram([UInt8](data))
            }
            if error == nil { self.receive() }
        }
    }
}
