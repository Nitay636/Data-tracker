import Foundation

/// Plain-text diagnostic log in the App Group container (`tunnel.log`), so tunnel behavior can be
/// read off a device. Capped in size and in the number of per-connection lines.
enum TunnelLog {
    private static let queue = DispatchQueue(label: "datatracker.log")
    private static let maximumBytes = 512 * 1024
    private static var detailLines = 0
    private static let maximumDetailLines = 400

    /// Under Library/Caches: the only part of the container `devicectl` can copy from a device.
    static var url: URL {
        let directory = AppGroup.containerURL.appendingPathComponent("Library/Caches", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("tunnel.log")
    }

    static func reset() {
        queue.async {
            detailLines = 0
            try? Data().write(to: url)
        }
        write("--- tunnel starting")
    }

    /// Always written.
    static func write(_ message: String) {
        let line = "\(timestamp()) \(message)\n"
        NSLog("DataTracker tunnel: \(message)")
        queue.async { append(line) }
    }

    /// Per-connection detail; only the first few hundred lines of a session are kept.
    static func detail(_ message: @autoclosure () -> String) {
        let text = message()
        queue.async {
            guard detailLines < maximumDetailLines else { return }
            detailLines += 1
            append("\(timestamp()) \(text)\n")
        }
    }

    private static func append(_ line: String) {
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            guard size < maximumBytes else { return }
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
