import Darwin
import Foundation
import DataTrackerCore

/// Reads the system-wide byte counters of every network interface.
///
/// `getifaddrs` exposes 32-bit counters that wrap at 4 GiB. The routing sysctl
/// (`NET_RT_IFLIST2`) exposes 64-bit counters; its values are only used when their low 32 bits
/// agree with `getifaddrs`, so a layout mismatch on some iOS version falls back safely.
enum InterfaceCounterReader {
    static func read() -> [InterfaceReading] {
        let narrow = readNarrow()
        let wide = readWide() ?? [:]
        return narrow.map { name, value in
            if let w = wide[name], agrees(wide: w.rx, narrow: value.rx), agrees(wide: w.tx, narrow: value.tx) {
                return InterfaceReading(name: name, received: w.rx, sent: w.tx, isWide: true)
            }
            return InterfaceReading(name: name, received: value.rx, sent: value.tx, isWide: false)
        }
    }

    /// Seconds since 1970 at which the device booted.
    static func bootTime() -> TimeInterval {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000
    }

    /// The two reads happen a few microseconds apart, so allow for traffic in between.
    private static func agrees(wide: UInt64, narrow: UInt64) -> Bool {
        let low = UInt32(truncatingIfNeeded: wide)
        let difference = Int64(Int32(bitPattern: low &- UInt32(truncatingIfNeeded: narrow)))
        return abs(difference) < 64 * 1024 * 1024
    }

    private static func readNarrow() -> [String: (rx: UInt64, tx: UInt64)] {
        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return result }
        defer { freeifaddrs(head) }

        var cursor = head
        while let pointer = cursor {
            let entry = pointer.pointee
            if let address = entry.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = entry.ifa_data {
                let stats = data.load(as: if_data.self)
                let name = String(cString: entry.ifa_name)
                result[name] = (UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes))
            }
            cursor = entry.ifa_next
        }
        return result
    }

    private static func readWide() -> [String: (rx: UInt64, tx: UInt64)]? {
        // CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0
        var mib: [Int32] = [4, 17, 0, 0, 6, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        // struct if_msghdr2 { u_short msglen; u_char version; u_char type; int addrs; int flags;
        //   u_short index; int snd_len, snd_maxlen, snd_drops, timer; struct if_data64 data; }
        // if_data64 starts at byte 32; ifi_ibytes / ifi_obytes are at +64 / +72 inside it.
        let rtmIfInfo2: UInt8 = 0x12
        let indexOffset = 12
        let receivedOffset = 32 + 64
        let sentOffset = 32 + 72

        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + 4 <= length {
                let messageLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength > 0, offset + messageLength <= length else { break }
                if raw[offset + 3] == rtmIfInfo2, messageLength >= sentOffset + 8 {
                    let index = raw.loadUnaligned(fromByteOffset: offset + indexOffset, as: UInt16.self)
                    let rx = raw.loadUnaligned(fromByteOffset: offset + receivedOffset, as: UInt64.self)
                    let tx = raw.loadUnaligned(fromByteOffset: offset + sentOffset, as: UInt64.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(index), &name) != nil {
                        result[String(cString: name)] = (rx, tx)
                    }
                }
                offset += messageLength
            }
        }
        return result
    }
}

/// Takes a reading of the interface counters and adds the difference to the database.
enum DeviceSampler {
    @discardableResult
    static func sample(into store: UsageStore? = SharedStore.open(), now: Date = Date()) -> Bool {
        guard let store else { return false }
        do {
            try UsageRecorder.record(readings: InterfaceCounterReader.read(),
                                     bootTime: InterfaceCounterReader.bootTime(),
                                     now: now, into: store)
            return true
        } catch {
            NSLog("DataTracker: sampling failed: \(error)")
            return false
        }
    }
}
