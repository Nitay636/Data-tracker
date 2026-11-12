import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public var code: Int32
    public var message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// On-device usage database. The same file (in the App Group container) is opened by the app,
/// the packet tunnel extension and the widget, so every write runs in a short `BEGIN IMMEDIATE`
/// transaction and the connection waits for other processes instead of failing.
public final class UsageStore: @unchecked Sendable {
    public let url: URL
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var transactionDepth = 0

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw SQLiteError(code: rc, message: message)
        }
        db = handle
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: Schema

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS iface_usage(
            hour INTEGER NOT NULL, kind INTEGER NOT NULL,
            rx INTEGER NOT NULL DEFAULT 0, tx INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(hour, kind)) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS domain_usage(
            hour INTEGER NOT NULL, domain TEXT NOT NULL, kind INTEGER NOT NULL,
            rx INTEGER NOT NULL DEFAULT 0, tx INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(hour, domain, kind)) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS counter_state(
            name TEXT PRIMARY KEY, rx INTEGER NOT NULL, tx INTEGER NOT NULL,
            boot REAL NOT NULL, ts REAL NOT NULL, wide INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS tracking_session(
            id INTEGER PRIMARY KEY AUTOINCREMENT, start REAL NOT NULL, end REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS tracking_session_end ON tracking_session(end);
        CREATE TABLE IF NOT EXISTS domain_mapping(domain TEXT PRIMARY KEY, target TEXT NOT NULL);
        """)
    }

    // MARK: Transactions

    /// Runs `body` inside `BEGIN IMMEDIATE … COMMIT`. Nested calls join the outer transaction.
    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if transactionDepth > 0 {
            transactionDepth += 1
            defer { transactionDepth -= 1 }
            return try body()
        }
        try execute("BEGIN IMMEDIATE")
        transactionDepth = 1
        do {
            let result = try body()
            transactionDepth = 0
            try execute("COMMIT")
            return result
        } catch {
            transactionDepth = 0
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: Interface usage

    public func addInterfaceUsage(_ values: [Int64: [CounterKind: ByteCount]]) throws {
        guard !values.isEmpty else { return }
        try transaction {
            let statement = try prepare("""
            INSERT INTO iface_usage(hour, kind, rx, tx) VALUES(?, ?, ?, ?)
            ON CONFLICT(hour, kind) DO UPDATE SET rx = rx + excluded.rx, tx = tx + excluded.tx
            """)
            for (hour, kinds) in values {
                for (kind, bytes) in kinds where !bytes.isZero {
                    try statement.reset()
                    statement.bind(1, hour)
                    statement.bind(2, Int64(kind.rawValue))
                    statement.bind(3, bytes.received)
                    statement.bind(4, bytes.sent)
                    try statement.stepDone()
                }
            }
        }
    }

    /// Rows with `fromHour <= hour < toHour`.
    public func interfaceUsage(fromHour: Int64, toHour: Int64) throws -> [InterfaceUsageRow] {
        try locked {
            let statement = try prepare("SELECT hour, kind, rx, tx FROM iface_usage WHERE hour >= ? AND hour < ?")
            statement.bind(1, fromHour)
            statement.bind(2, toHour)
            var rows: [InterfaceUsageRow] = []
            while try statement.step() {
                guard let kind = CounterKind(rawValue: Int(statement.int64(1))) else { continue }
                rows.append(InterfaceUsageRow(hour: statement.int64(0), kind: kind,
                                              bytes: ByteCount(received: statement.int64(2), sent: statement.int64(3))))
            }
            return rows
        }
    }

    // MARK: Domain usage

    public func addDomainUsage(_ values: [DomainUsageKey: ByteCount]) throws {
        guard !values.isEmpty else { return }
        try transaction {
            let statement = try prepare("""
            INSERT INTO domain_usage(hour, domain, kind, rx, tx) VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(hour, domain, kind) DO UPDATE SET rx = rx + excluded.rx, tx = tx + excluded.tx
            """)
            for (key, bytes) in values where !bytes.isZero {
                try statement.reset()
                statement.bind(1, key.hour)
                statement.bind(2, key.domain)
                statement.bind(3, Int64(key.kind.rawValue))
                statement.bind(4, bytes.received)
                statement.bind(5, bytes.sent)
                try statement.stepDone()
            }
        }
    }

    public func domainUsage(fromHour: Int64, toHour: Int64) throws -> [DomainUsageRow] {
        try locked {
            let statement = try prepare("SELECT hour, domain, kind, rx, tx FROM domain_usage WHERE hour >= ? AND hour < ?")
            statement.bind(1, fromHour)
            statement.bind(2, toHour)
            var rows: [DomainUsageRow] = []
            while try statement.step() {
                guard let kind = NetworkKind(rawValue: Int(statement.int64(2))) else { continue }
                rows.append(DomainUsageRow(hour: statement.int64(0), domain: statement.string(1), kind: kind,
                                           bytes: ByteCount(received: statement.int64(3), sent: statement.int64(4))))
            }
            return rows
        }
    }

    // MARK: Counter state

    public func counterStates() throws -> [String: CounterSnapshot] {
        try locked {
            let statement = try prepare("SELECT name, rx, tx, boot, ts, wide FROM counter_state")
            var result: [String: CounterSnapshot] = [:]
            while try statement.step() {
                result[statement.string(0)] = CounterSnapshot(
                    received: UInt64(bitPattern: statement.int64(1)),
                    sent: UInt64(bitPattern: statement.int64(2)),
                    bootTime: statement.double(3),
                    timestamp: statement.double(4),
                    isWide: statement.int64(5) != 0)
            }
            return result
        }
    }

    public func setCounterState(_ snapshot: CounterSnapshot, for name: String) throws {
        try transaction {
            let statement = try prepare("INSERT OR REPLACE INTO counter_state(name, rx, tx, boot, ts, wide) VALUES(?, ?, ?, ?, ?, ?)")
            statement.bind(1, name)
            statement.bind(2, Int64(bitPattern: snapshot.received))
            statement.bind(3, Int64(bitPattern: snapshot.sent))
            statement.bind(4, snapshot.bootTime)
            statement.bind(5, snapshot.timestamp)
            statement.bind(6, Int64(snapshot.isWide ? 1 : 0))
            try statement.stepDone()
        }
    }

    // MARK: Tracking sessions

    public func beginSession(at date: Date) throws -> Int64 {
        try transaction { () throws -> Int64 in
            let statement = try prepare("INSERT INTO tracking_session(start, end) VALUES(?, ?)")
            statement.bind(1, date.timeIntervalSince1970)
            statement.bind(2, date.timeIntervalSince1970)
            try statement.stepDone()
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func extendSession(_ id: Int64, to date: Date) throws {
        try transaction {
            let statement = try prepare("UPDATE tracking_session SET end = MAX(end, ?) WHERE id = ?")
            statement.bind(1, date.timeIntervalSince1970)
            statement.bind(2, id)
            try statement.stepDone()
        }
    }

    public func sessions(overlapping start: Date, _ end: Date) throws -> [TrackingSession] {
        try locked {
            let statement = try prepare("SELECT id, start, end FROM tracking_session WHERE end > ? AND start < ? ORDER BY start")
            statement.bind(1, start.timeIntervalSince1970)
            statement.bind(2, end.timeIntervalSince1970)
            var result: [TrackingSession] = []
            while try statement.step() {
                result.append(TrackingSession(id: statement.int64(0),
                                              start: Date(timeIntervalSince1970: statement.double(1)),
                                              end: Date(timeIntervalSince1970: statement.double(2))))
            }
            return result
        }
    }

    // MARK: Domain assignments

    /// Domain → `EntryID.key` (`app:<id>` or `custom:<name>`).
    public func mappings() throws -> [String: String] {
        try locked {
            let statement = try prepare("SELECT domain, target FROM domain_mapping")
            var result: [String: String] = [:]
            while try statement.step() { result[statement.string(0)] = statement.string(1) }
            return result
        }
    }

    /// Pass `nil` to remove an assignment.
    public func setMapping(domain: String, target: EntryID?) throws {
        try transaction {
            if let target {
                let statement = try prepare("INSERT OR REPLACE INTO domain_mapping(domain, target) VALUES(?, ?)")
                statement.bind(1, domain)
                statement.bind(2, target.key)
                try statement.stepDone()
            } else {
                let statement = try prepare("DELETE FROM domain_mapping WHERE domain = ?")
                statement.bind(1, domain)
                try statement.stepDone()
            }
        }
    }

    // MARK: Info

    public func earliestHour() throws -> Int64? {
        try locked {
            let statement = try prepare("SELECT MIN(hour) FROM iface_usage")
            guard try statement.step(), !statement.isNull(0) else { return nil }
            return statement.int64(0)
        }
    }

    public func fileSize() -> Int64 {
        let paths = [url.path, url.path + "-wal"]
        return paths.reduce(Int64(0)) { sum, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return sum + size
        }
    }

    // MARK: Plumbing

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw SQLiteError(code: rc, message: message)
        }
    }

    private func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
        return Statement(handle: statement, db: db)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class Statement {
    let handle: OpaquePointer
    let db: OpaquePointer?

    init(handle: OpaquePointer, db: OpaquePointer?) {
        self.handle = handle
        self.db = db
    }

    deinit { sqlite3_finalize(handle) }

    func bind(_ index: Int32, _ value: Int64) { sqlite3_bind_int64(handle, index, value) }
    func bind(_ index: Int32, _ value: Double) { sqlite3_bind_double(handle, index, value) }
    func bind(_ index: Int32, _ value: String) { sqlite3_bind_text(handle, index, value, -1, sqliteTransient) }

    func reset() throws {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    /// Returns `true` while there are rows.
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db)))
    }

    func stepDone() throws {
        _ = try step()
    }

    func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }
    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }
    func string(_ column: Int32) -> String {
        guard let text = sqlite3_column_text(handle, column) else { return "" }
        return String(cString: text)
    }
}
