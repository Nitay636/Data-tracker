import Foundation
import NetworkExtension
import Tun2SocksKit
import DataTrackerCore

/// On-device "VPN" that never leaves the phone. Every connection is forwarded to its real
/// destination by `LocalSocksServer`, which counts bytes per domain and per network.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let meter: DomainTrafficAccumulator
    private let server: LocalSocksServer
    private let flushQueue = DispatchQueue(label: "datatracker.flush")
    private var flushTimer: DispatchSourceTimer?
    private var sessionID: Int64?

    override init() {
        let meter = DomainTrafficAccumulator()
        self.meter = meter
        self.server = LocalSocksServer { label, kind, received, sent in
            meter.add(domain: label, kind: kind, received: received, sent: sent)
        }
        super.init()
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        server.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completionHandler(error)
            case .success(let port):
                self.setTunnelNetworkSettings(Self.networkSettings()) { error in
                    if let error {
                        self.server.stop()
                        completionHandler(error)
                        return
                    }
                    Socks5Tunnel.run(withConfig: .string(content: TunnelConfiguration.yaml(socksPort: port))) { code in
                        NSLog("DataTracker tunnel: hev-socks5-tunnel exited with code \(code)")
                    }
                    self.beginTracking()
                    completionHandler(nil)
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        flushTimer?.cancel()
        flushTimer = nil
        Socks5Tunnel.quit()
        server.stop()
        flushQueue.async {
            self.flush()
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        flushQueue.async {
            if messageData == TunnelMessage.flush { self.flush() }
            completionHandler?(Data("ok".utf8))
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        flushQueue.async {
            self.flush()
            completionHandler()
        }
    }

    // MARK: Tracking

    private func beginTracking() {
        flushQueue.async {
            // Establish a fresh counter baseline so the session's first flush is attributed correctly.
            DeviceSampler.sample()
            if let store = SharedStore.open() {
                self.sessionID = try? store.beginSession(at: Date())
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: flushQueue)
        timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume()
        flushTimer = timer
    }

    /// Writes buffered per-domain usage, samples the interface counters and extends the session.
    /// Runs on `flushQueue`.
    private func flush() {
        guard let store = SharedStore.open() else { return }
        let now = Date()
        let drained = meter.drain()
        do {
            try store.addDomainUsage(drained)
        } catch {
            meter.restore(drained)
            NSLog("DataTracker tunnel: write failed: \(error)")
        }
        DeviceSampler.sample(into: store, now: now)
        if let sessionID {
            try? store.extendSession(sessionID, to: now)
        }
    }

    // MARK: Network settings

    private static func networkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: TunnelConfiguration.mtu)

        let ipv4 = NEIPv4Settings(addresses: [TunnelConfiguration.tunnelAddress],
                                  subnetMasks: [TunnelConfiguration.tunnelSubnetMask])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // Local network traffic (printers, AirPlay, routers) does not use internet data; leave it alone.
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "224.0.0.0", subnetMask: "240.0.0.0")
        ]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: [TunnelConfiguration.tunnelIPv6Address], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        ipv6.excludedRoutes = [
            NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: 10),
            NEIPv6Route(destinationAddress: "ff00::", networkPrefixLength: 8)
        ]
        settings.ipv6Settings = ipv6

        // Answered by hev-socks5-tunnel's mapped DNS, so every connection arrives with its host name.
        let dns = NEDNSSettings(servers: [TunnelConfiguration.dnsAddress])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        return settings
    }
}
