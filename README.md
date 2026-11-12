# DataTracker

An iOS 18 app that tracks internet data usage on your iPhone:

- **Wi-Fi vs cellular** totals, including download and upload
- **Day / Week / Month** views, with the option to page back through earlier periods. Month can be your carrier billing cycle, the last 30 days, or the calendar month.
- **Top apps**, each split into Wi-Fi and cellular. Tapping an app shows its usage **by hour** (Day view) or **by day** (Week/Month view) and lists the domains behind it.
- **iOS & System Services** and **Personal Hotspot** shown as separate entries
- **Home-screen widget** (small and medium) showing today's usage and top apps
- **Auto-resume:** tracking turns itself back on after you've used another VPN (can be turned off in Settings)

Everything stays on the device. Usage history is kept indefinitely.

## How it works

| What | Where it comes from | Accuracy |
|---|---|---|
| Wi-Fi / cellular totals | The iPhone's network-interface byte counters (`en0`, `pdp_ip*`), read whenever the app, the widget, the VPN extension, or a background refresh runs | Exact. Counters reset when the phone restarts, and the app detects that. |
| Personal Hotspot | The hotspot bridge interface (`bridge100`) | Exact. It's part of cellular. |
| Per-app usage | An **on-device VPN** (Network Extension packet tunnel). Every connection passes through a local proxy inside the extension, which counts bytes per domain and per network. The built-in catalog (about 100 apps) and your own assignments then group domains into apps. | A good estimate. Domains shared by several apps (Google, Amazon CDNs) can't be split between them. |
| iOS & System Services | Apple domains seen by the VPN, plus the **difference** between the interface totals and what the VPN saw. That difference is traffic iOS sends around every VPN, such as push and some Apple services. | An estimate. It also absorbs a few percent of TCP/TLS overhead. |
| Not tracked | Usage from periods when the VPN was off or paused, for example while another VPN was on | — |

Apple doesn't let third-party apps read the per-app numbers shown in Settings → Cellular, so the VPN is the only way to get per-app data.

### Tracking VPN and other VPNs

iOS runs only one VPN at a time. When you connect another VPN, iOS disconnects this one and tracking pauses. The totals keep counting and show up under **Not tracked**. With **Settings → Resume after another VPN** turned on, the app checks whether any VPN is still connected and turns tracking back on once none is. The check runs:

- right away when you open the app
- in background refresh (iOS decides when; usually within the hour)

For an instant switch, use the **Start Tracking** App Shortcut, which you can put in Control Center, on the Action button, or in a Shortcuts automation.

## Project layout

```
App/                 SwiftUI app (screens, VPN controller, background refresh, App Intents)
Tunnel/              Packet tunnel extension: PacketTunnelProvider + local SOCKS5 proxy that counts bytes
Widget/              WidgetKit extension
Shared/Common/       Code used by app, tunnel and widget (App Group, interface counter reader)
Shared/UI/           SwiftUI helpers used by app and widget
Packages/DataTrackerCore/   Platform-independent logic with unit tests:
                     period math, counter deltas, SQLite store, domain → app catalog, report builder,
                     SOCKS5 framing, TLS SNI parsing
project.yml          XcodeGen spec (the .xcodeproj is generated, not committed)
Config/Signing.xcconfig     Your Team ID and bundle ID prefix
```

The VPN uses [Tun2SocksKit](https://github.com/EbrahimTahernejad/Tun2SocksKit), a wrapper around [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) (both MIT licensed). It turns the tunnel's packets into connections and answers DNS with mapped addresses, so each connection reaches the proxy with its host name. The proxy (`Tunnel/LocalSocksServer.swift`) opens the real connection with Network.framework and records bytes per domain and per network (Wi-Fi or cellular). It reads no content apart from the TLS server name or HTTP `Host` header of connections that were opened to a bare IP address.

## Building

Requirements: a Mac with Xcode 16 or newer, and a **paid** Apple Developer account (Network Extensions need it).

1. `brew install xcodegen`
2. Edit `Config/Signing.xcconfig`: set `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX`.
3. `xcodegen generate && open DataTracker.xcodeproj`
4. Under Signing & Capabilities, Xcode's automatic signing should create the App Group and Network Extension capabilities for all three targets. If it doesn't, add them on developer.apple.com: App Group `group.<prefix>.datatracker`, plus Network Extensions → Packet Tunnel on the app ID and the `.tunnel` ID.
5. Run on a **real iPhone**. Network Extensions don't work in the Simulator.
6. In the app, go to Settings → Per-app tracking → Continue → **Allow** in the iOS prompt.

Run the logic tests with `swift test --package-path Packages/DataTrackerCore`. CI (`.github/workflows/ci.yml`) runs them and builds all three targets unsigned on every push.

## What to check on a device first

These parts can't be tested in CI:

- Browsing, video, WhatsApp/FaceTime calls, and QUIC apps (YouTube, Instagram) all work with tracking on.
- Per-app numbers appear within about 30 seconds of use.
- Turning on another VPN pauses tracking. Turning it off resumes tracking when you open the app.
- The memory use of the `DataTrackerTunnel` process stays well under iOS's 50 MB limit for extensions. Check in Xcode → Debug Navigator while attached to the extension.
