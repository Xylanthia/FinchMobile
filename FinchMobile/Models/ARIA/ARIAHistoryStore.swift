import Foundation
import Observation
import SQLite3

/// Sources the handheld logs durably to flash (firmware aria_log.h, GET /api/log).
enum ARIALogSource: String, CaseIterable, Identifiable {
    case wifi, ble, subghz, uas

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ble: return "BLE"
        case .subghz: return "Sub-GHz"
        case .uas: return "UAS"
        }
    }

    /// Sub-GHz records carry the full waveform (~4 KB each), so smaller pages.
    var pageLimit: Int { self == .subghz ? 200 : 500 }
}

enum ARIAHistoryValue {
    case wifi(ARIAWiFiDevice)
    case ble(ARIABLEDeviceRecord)
    case subghz(ARIASubGHzCapture)
    case uas(ARIAUASRecord)
}

/// One decoded record ready to persist: `json` is the evidence stored and exported verbatim,
/// `value` is what the UI shows.
struct ARIAHistoryRow {
    let source: ARIALogSource
    let key: String
    let json: String
    let value: ARIAHistoryValue
    let fromLog: Bool
}

// MARK: - Firmware record → app record mapping (pure, runs off the main actor)

enum ARIAHistoryCodec {
    static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func decode<T: Decodable>(_ dict: [String: Any], as type: T.Type) -> T? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func key(_ source: ARIALogSource, _ row: [String: Any]) -> String? {
        switch source {
        case .wifi, .ble:
            let mac = row["mac"] as? String ?? row["address"] as? String ?? row["key"] as? String
            return mac.map { $0.uppercased() }
        case .subghz:
            // Same identity for a capture whether it came from the live ring or the flash log
            // (matches ARIASubGHzCapture.id).
            guard let seq = int(row["radio_sequence"] ?? row["sequence"]) else { return nil }
            let boot = int(row["radio_boot_id"] ?? row["boot_id"] ?? row["boot"]) ?? 0
            return "\(seq)-\(boot)"
        case .uas:
            return (row["uas_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Log record (`source` + `event` + firmware fields) or live snapshot row → typed value.
    /// Never returns nil for a keyed row: a record that fails typed decoding is still shown
    /// (identity only) so lists, counts and the export always agree.
    static func value(_ source: ARIALogSource, _ row: [String: Any], key: String) -> ARIAHistoryValue {
        switch source {
        case .wifi, .ble:
            var input = row
            input["band"] = input["band"] ?? source.rawValue
            let normalized = ARIAJSONResponse.normalizeDevice(input)?.row ?? input
            if source == .wifi {
                return .wifi(decode(normalized, as: ARIAWiFiDevice.self) ?? ARIAWiFiDevice(mac: key))
            }
            return .ble(decode(normalized, as: ARIABLEDeviceRecord.self) ?? ARIABLEDeviceRecord(address: key))
        case .subghz:
            let mapped = row["radio_sequence"] != nil ? subghzFromLog(row) : row
            let fallback = ARIASubGHzCapture(sequence: int(mapped["sequence"]) ?? 0, boot: int(mapped["boot"]))
            return .subghz(decode(mapped, as: ARIASubGHzCapture.self) ?? fallback)
        case .uas:
            return .uas(decode(row, as: ARIAUASRecord.self) ?? ARIAUASRecord(uasID: key))
        }
    }

    /// Flash-log Sub-GHz record (aria_log.cpp appendSubghz) → ARIASubGHzCapture shape.
    static func subghzFromLog(_ r: [String: Any]) -> [String: Any] {
        var row: [String: Any] = [:]
        row["sequence"] = int(r["radio_sequence"])
        row["boot"] = int(r["radio_boot_id"])
        row["frequency_mhz"] = r["frequency_mhz"]
        if let rssi = r["rssi"] as? NSNumber { row["rssi"] = Int(rssi.doubleValue.rounded()) }
        row["pulse_count"] = int(r["pulse_count"])
        row["duration_us"] = int(r["duration_us"])
        let state = r["decode_state"] as? String ?? "UNKNOWN"
        let proto = r["protocol"] as? String ?? "UNKNOWN"
        var detail = [state, proto, r["rx_modulation"] as? String ?? ""].filter { !$0.isEmpty }
        if r["pulse_overflow"] as? Bool == true { detail.append("MAX-PULSES") }
        if r["capture_timeout"] as? Bool == true { detail.append("CAPTURE-TIMEOUT") }
        row["detail"] = detail.joined(separator: " · ")
        row["decode"] = [
            "raw_hex": r["data_hex"] ?? "",
            "decoded_hex": r["decoded_hex"] ?? "",
            "decoded_status": state,
            "verification_status": r["protocol_validated"] as? Bool == true ? "VERIFIED" : state,
            "raw_availability": "LOGGED_TO_HANDHELD_FLASH",
        ] as [String: Any]
        return row
    }

    static func row(_ source: ARIALogSource, _ dict: [String: Any], fromLog: Bool) -> ARIAHistoryRow? {
        guard let key = key(source, dict),
              JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return ARIAHistoryRow(source: source, key: key, json: json,
                              value: value(source, dict, key: key), fromLog: fromLog)
    }
}

// MARK: - SQLite persistence (confined to one serial queue)

/// Durable local record of everything the handheld has reported. Rows are never deleted by
/// going out of range; only an explicit operator clear removes them.
final class ARIAHistoryDB {
    struct Cursor { var epoch: String; var lastSeq: Int; var logRecords: Int }
    struct Stored { let source: ARIALogSource; let key: String; let json: String; let firstSeen: Date; let lastSeen: Date }

    private let queue = DispatchQueue(label: "finch.aria.history.db")
    private var db: OpaquePointer?
    private(set) var openError: String?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        queue.sync { self.open() }
    }

    deinit { sqlite3_close(db) }

    func run<T>(_ work: @escaping (ARIAHistoryDB) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work(self)) }
        }
    }

    private func open() {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            let url = dir.appendingPathComponent("ARIAHistory.sqlite")
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
                openError = "history store: \(lastMessage)"
                return
            }
            exec("PRAGMA journal_mode=WAL")
            exec("PRAGMA synchronous=NORMAL")
            exec("""
                CREATE TABLE IF NOT EXISTS records(
                  source TEXT NOT NULL, key TEXT NOT NULL, json TEXT NOT NULL, origin TEXT NOT NULL,
                  first_seen REAL NOT NULL, last_seen REAL NOT NULL, log_records INTEGER NOT NULL,
                  PRIMARY KEY(source, key))
                """)
            exec("CREATE TABLE IF NOT EXISTS cursors(source TEXT PRIMARY KEY, epoch TEXT NOT NULL, last_seq INTEGER NOT NULL, log_records INTEGER NOT NULL)")
        } catch {
            openError = "history store: \(error.localizedDescription)"
        }
    }

    private var lastMessage: String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "not open" }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ text: String) {
        sqlite3_bind_text(stmt, index, text, -1, Self.transient)
    }

    private func text(_ stmt: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }

    /// Upserts rows and (for log pages) advances that source's cursor in ONE transaction, so
    /// a crash can never record a cursor past records that were not stored.
    @discardableResult
    func upsert(_ rows: [ARIAHistoryRow], at time: Date, cursor: (ARIALogSource, Cursor)?) -> Bool {
        guard db != nil else { return false }
        exec("BEGIN IMMEDIATE")
        var stmt: OpaquePointer?
        let sql = """
            INSERT INTO records(source, key, json, origin, first_seen, last_seen, log_records)
            VALUES(?1, ?2, ?3, ?4, ?5, ?5, ?6)
            ON CONFLICT(source, key) DO UPDATE SET
              json = CASE WHEN source = 'subghz' AND origin = 'log' AND excluded.origin = 'live'
                          THEN json ELSE excluded.json END,
              origin = CASE WHEN origin = 'log' THEN 'log' ELSE excluded.origin END,
              last_seen = max(last_seen, excluded.last_seen),
              log_records = log_records + excluded.log_records
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            exec("ROLLBACK")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        var ok = true
        for row in rows {
            sqlite3_reset(stmt)
            bind(stmt, 1, row.source.rawValue)
            bind(stmt, 2, row.key)
            bind(stmt, 3, row.json)
            bind(stmt, 4, row.fromLog ? "log" : "live")
            sqlite3_bind_double(stmt, 5, time.timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 6, row.fromLog ? 1 : 0)
            if sqlite3_step(stmt) != SQLITE_DONE { ok = false; break }
        }
        if ok, let cursor {
            let (source, c) = cursor
            var cs: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO cursors(source, epoch, last_seq, log_records) VALUES(?1, ?2, ?3, ?4)", -1, &cs, nil) == SQLITE_OK {
                bind(cs, 1, source.rawValue)
                bind(cs, 2, c.epoch)
                sqlite3_bind_int64(cs, 3, Int64(c.lastSeq))
                sqlite3_bind_int64(cs, 4, Int64(c.logRecords))
                ok = sqlite3_step(cs) == SQLITE_DONE
            } else {
                ok = false
            }
            sqlite3_finalize(cs)
        }
        exec(ok ? "COMMIT" : "ROLLBACK")
        return ok
    }

    func cursors() -> [ARIALogSource: Cursor] {
        var out: [ARIALogSource: Cursor] = [:]
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT source, epoch, last_seq, log_records FROM cursors", -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let source = ARIALogSource(rawValue: text(stmt, 0)) else { continue }
            out[source] = Cursor(epoch: text(stmt, 1), lastSeq: Int(sqlite3_column_int64(stmt, 2)),
                                 logRecords: Int(sqlite3_column_int64(stmt, 3)))
        }
        return out
    }

    /// Visits every stored row in insertion order (oldest first).
    func forEach(_ body: (Stored) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT source, key, json, first_seen, last_seen FROM records ORDER BY rowid", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let source = ARIALogSource(rawValue: text(stmt, 0)) else { continue }
            body(Stored(source: source, key: text(stmt, 1), json: text(stmt, 2),
                        firstSeen: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                        lastSeen: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))))
        }
    }

    /// Streams the whole store to `url` as one JSON object, row by row — no in-memory array
    /// and no size cap. The summary is written last, from the counts actually written, so it
    /// always equals the exported array lengths. Runs inside one read transaction.
    @discardableResult
    func writeExport(to url: URL, header: [String: Any], liveKeys: Set<String>,
                     summary: ([ARIALogSource: Int]) -> [String: Any]) throws -> [ARIALogSource: Int] {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let iso = ISO8601DateFormatter()
        var buffer = Data()
        func emit(_ s: String) throws {
            buffer.append(Data(s.utf8))
            if buffer.count >= 256 * 1024 { try handle.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) }
        }
        func json(_ object: Any) -> String {
            guard JSONSerialization.isValidJSONObject(object),
                  let d = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "null" }
            return String(decoding: d, as: UTF8.self)
        }

        exec("BEGIN")
        defer { exec("COMMIT") }
        var counts: [ARIALogSource: Int] = [:]
        try emit("{")
        for (k, v) in header.sorted(by: { $0.key < $1.key }) {
            try emit(String(json([k]).dropFirst().dropLast()) + ":" + json(v) + ",")
        }
        for source in ARIALogSource.allCases {
            try emit("\"\(source.rawValue)\":[")
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT key, json, origin, first_seen, last_seen, log_records FROM records WHERE source = ?1 ORDER BY rowid", -1, &stmt, nil) == SQLITE_OK else {
                throw ARIAClient.Failure(message: "export query failed: \(lastMessage)", statusCode: nil)
            }
            bind(stmt, 1, source.rawValue)
            var n = 0
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = text(stmt, 0)
                let meta: [String: Any] = [
                    "key": key,
                    "origin": text(stmt, 2),
                    "phone_first_received": iso.string(from: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))),
                    "phone_last_received": iso.string(from: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))),
                    "handheld_log_records": Int(sqlite3_column_int64(stmt, 5)),
                    "in_range_at_export": liveKeys.contains("\(source.rawValue):\(key)"),
                ]
                // Splice the stored firmware JSON in verbatim as "record" (evidence, not re-encoded).
                let metaPrefix = String(json(meta).dropLast())
                try emit((n == 0 ? "" : ",") + metaPrefix + ",\"record\":" + text(stmt, 1) + "}")
                n += 1
            }
            sqlite3_finalize(stmt)
            counts[source] = n
            try emit("],")
        }
        try emit("\"summary\":\(json(summary(counts)))}")
        try handle.write(contentsOf: buffer)
        return counts
    }

    func clear() {
        exec("DELETE FROM records")
        exec("DELETE FROM cursors")
    }
}

// MARK: - Observable history (UI state)

/// Everything ever reported by the handheld this session and before, backfilled from
/// /api/log and kept current by /api/stream and the live snapshot. A device that leaves
/// range keeps its row and its place in every count; only its live marker expires.
@MainActor
@Observable
final class ARIAHistory {
    enum Backfill: Equatable {
        case idle
        case loading(loaded: Int, total: Int)
        case complete
        case unavailable(String)
    }

    private struct Slot {
        var value: ARIAHistoryValue
        var firstSeen: Date
        var lastSeen: Date
        var order: Int
    }

    /// A live marker older than this means "not currently in range".
    static let liveWindow: TimeInterval = 60

    private(set) var wifi: [ARIAWiFiDevice] = []
    private(set) var ble: [ARIABLEDeviceRecord] = []
    private(set) var subghz: [ARIASubGHzCapture] = []
    private(set) var uas: [ARIAUASRecord] = []

    private(set) var backfill: [ARIALogSource: Backfill] = [:]
    /// Last /api/log/stats response (the handheld's own totals), verbatim.
    private(set) var handheldStats: [String: Any] = [:]
    private(set) var loaded = false
    private(set) var storeError: String?

    private var slots: [ARIALogSource: [String: Slot]] = [:]
    private var liveSeen: [String: Date] = [:]
    private(set) var cursors: [ARIALogSource: ARIAHistoryDB.Cursor] = [:]
    private var nextOrder = 0
    private let db = ARIAHistoryDB()

    init() {
        storeError = db.openError
        Task { await load() }
    }

    // MARK: Counts (one canonical pair per source, used by every screen)

    func total(_ source: ARIALogSource) -> Int { slots[source]?.count ?? 0 }

    func liveCount(_ source: ARIALogSource) -> Int {
        let prefix = source.rawValue + ":"
        let cutoff = Date().addingTimeInterval(-Self.liveWindow)
        return liveSeen.filter { $0.key.hasPrefix(prefix) && $0.value >= cutoff }.count
    }

    func isLive(_ source: ARIALogSource, _ id: String) -> Bool {
        guard let seen = liveSeen["\(source.rawValue):\(id.uppercased())"] ?? liveSeen["\(source.rawValue):\(id)"] else { return false }
        return seen >= Date().addingTimeInterval(-Self.liveWindow)
    }

    func lastSeen(_ source: ARIALogSource, _ id: String) -> Date? {
        (slots[source]?[id.uppercased()] ?? slots[source]?[id])?.lastSeen
    }

    /// The handheld's own durable total for a source (/api/log/stats total_available).
    func handheldTotal(_ source: ARIALogSource) -> Int? {
        let sources = handheldStats["sources"] as? [String: Any]
        return ARIAHistoryCodec.int((sources?[source.rawValue] as? [String: Any])?["total_available"])
    }

    /// "Total seen" text; never a bare 0 while history is still arriving.
    func totalText(_ source: ARIALogSource) -> String {
        if !loaded { return "loading…" }
        if case .loading(let done, let all) = backfill[source] {
            return "loading \(done.formatted()) / \(all.formatted())"
        }
        return total(source).formatted()
    }

    /// Combined progress for the banner, nil when nothing is loading.
    var progressText: String? {
        var done = 0, all = 0, active = false
        for case .loading(let d, let t) in backfill.values { done += d; all += t; active = true }
        guard active || !loaded else { return nil }
        return loaded ? "Loading capture history: \(done.formatted()) / \(all.formatted())" : "Loading capture history…"
    }

    // MARK: Loading

    private func load() async {
        typealias Decoded = (ARIALogSource, String, ARIAHistoryValue, Date, Date)
        let (items, cursors): ([Decoded], [ARIALogSource: ARIAHistoryDB.Cursor]) = await db.run { db in
            var items: [Decoded] = []
            db.forEach { s in
                guard let data = s.json.data(using: .utf8),
                      let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
                items.append((s.source, s.key, ARIAHistoryCodec.value(s.source, dict, key: s.key), s.firstSeen, s.lastSeen))
            }
            return (items, db.cursors())
        }
        for (source, key, value, first, last) in items {
            slots[source, default: [:]][key] = Slot(value: value, firstSeen: first, lastSeen: last, order: nextOrder)
            nextOrder += 1
        }
        self.cursors.merge(cursors) { current, _ in current }
        loaded = true
        rebuildAll()
    }

    // MARK: Ingest

    /// `current` = the rows describe the device as it is now (snapshot / stream); backfilled
    /// history only fills in keys the app has never seen and never overwrites newer state.
    private func merge(_ rows: [ARIAHistoryRow], at time: Date, current: Bool) -> Set<ARIALogSource> {
        var touched = Set<ARIALogSource>()
        for row in rows {
            touched.insert(row.source)
            if var slot = slots[row.source]?[row.key] {
                // A Sub-GHz capture is immutable: the flash-log record (full waveform) replaces a
                // live-ring row, never the reverse.
                if (row.source == .subghz) ? row.fromLog : current { slot.value = row.value }
                slot.lastSeen = max(slot.lastSeen, time)
                slots[row.source]?[row.key] = slot
            } else {
                slots[row.source, default: [:]][row.key] = Slot(value: row.value, firstSeen: time, lastSeen: time, order: nextOrder)
                nextOrder += 1
            }
            if current { liveSeen["\(row.source.rawValue):\(row.key)"] = time }
        }
        return touched
    }

    /// The current /api/devices + Sub-GHz snapshot: everything in it is live now and
    /// is also written to the store (so live is always a subset of total).
    func ingestLive(_ snapshot: ARIASessionExport) async {
        guard let root = (try? JSONSerialization.jsonObject(with: snapshot.raw)) as? [String: Any] else { return }
        let now = Date()
        let rows: [ARIAHistoryRow] = await db.run { db in
            var rows: [ARIAHistoryRow] = []
            for source in ARIALogSource.allCases {
                for dict in root[source.rawValue] as? [[String: Any]] ?? [] {
                    if let row = ARIAHistoryCodec.row(source, dict, fromLog: false) { rows.append(row) }
                }
            }
            db.upsert(rows, at: now, cursor: nil)
            return rows
        }
        // Sub-GHz "live" = still in the handheld's RAM ring, replaced wholesale each snapshot.
        liveSeen = liveSeen.filter { !$0.key.hasPrefix("subghz:") }
        rebuild(merge(rows, at: now, current: true))
        expireLive()
    }

    /// /api/stream "live" event: devices updated since the last event.
    func applyLiveUpdates(_ event: [String: Any]) {
        let now = Date()
        for update in event["updates"] as? [[String: Any]] ?? [] {
            guard let mac = (update["mac"] as? String)?.uppercased(),
                  let band = update["band"] as? String, band == "wifi" || band == "ble" else { continue }
            let age = Double(ARIAHistoryCodec.int(update["age_ms"]) ?? 0) / 1000
            liveSeen["\(band):\(mac)"] = now.addingTimeInterval(-age)
        }
        expireLive()
    }

    private func expireLive() {
        let cutoff = Date().addingTimeInterval(-Self.liveWindow)
        liveSeen = liveSeen.filter { $0.key.hasPrefix("subghz:") || $0.value >= cutoff }
    }

    /// Records from one /api/log page or one /api/stream "record" event, all for `source` and
    /// the handheld log `epoch`. Only seq > cursor is taken, so a page and the stream racing
    /// over the same range never double-count. Returns false on a gap (caller re-pages).
    @discardableResult
    func ingestLog(_ source: ARIALogSource, epoch: String, records: [[String: Any]], requireContiguous: Bool) async -> Bool {
        var cursor = cursors[source] ?? ARIAHistoryDB.Cursor(epoch: epoch, lastSeq: 0, logRecords: 0)
        if cursor.epoch != epoch { cursor = ARIAHistoryDB.Cursor(epoch: epoch, lastSeq: 0, logRecords: cursor.logRecords) }
        let fresh = records
            .compactMap { r -> (Int, [String: Any])? in ARIAHistoryCodec.int(r["seq"]).map { ($0, r) } }
            .filter { $0.0 > cursor.lastSeq }
            .sorted { $0.0 < $1.0 }
        guard let firstSeq = fresh.first?.0 else { return true }
        if requireContiguous && firstSeq != cursor.lastSeq + 1 { return false }
        cursor.lastSeq = fresh.last!.0
        cursor.logRecords += fresh.count
        cursors[source] = cursor   // claim the range before suspending

        let now = Date()
        let saved = cursor
        let (rows, ok): ([ARIAHistoryRow], Bool) = await db.run { db in
            let rows = fresh.compactMap { ARIAHistoryCodec.row(source, $0.1, fromLog: true) }
            return (rows, db.upsert(rows, at: now, cursor: (source, saved)))
        }
        if !ok { storeError = "history store write failed; records kept in memory only" }
        // Stream records are sightings happening now; backfilled pages are history.
        rebuild(merge(rows, at: now, current: requireContiguous))
        return true
    }

    func setBackfill(_ source: ARIALogSource, _ state: Backfill) { backfill[source] = state }
    func setHandheldStats(_ stats: [String: Any]) { handheldStats = stats }

    // MARK: Export

    func writeExport(to url: URL, liveSnapshot: Data) async throws -> [ARIALogSource: Int] {
        var live = Set<String>()
        let cutoff = Date().addingTimeInterval(-Self.liveWindow)
        for (k, v) in liveSeen where v >= cutoff || k.hasPrefix("subghz:") { live.insert(k) }
        var liveCounts: [String: Int] = [:]
        var handheld: [String: Any] = [:]
        var ingested: [String: Int] = [:]
        for source in ARIALogSource.allCases {
            liveCounts[source.rawValue] = liveCount(source)
            handheld[source.rawValue] = handheldTotal(source).map { $0 as Any } ?? NSNull()
            ingested[source.rawValue] = cursors[source]?.logRecords ?? 0
        }
        let snapshotObject = (try? JSONSerialization.jsonObject(with: liveSnapshot)) ?? NSNull()
        let header: [String: Any] = [
            "schema": "finch.aria.history.v1",
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "handheld_log_stats": handheldStats.isEmpty ? NSNull() as Any : handheldStats as Any,
            "live_snapshot_at_export": snapshotObject,
        ]
        let liveWindow = Int(Self.liveWindow)
        return try await db.run { db -> Result<[ARIALogSource: Int], Error> in
            Result {
                try db.writeExport(to: url, header: header, liveKeys: live) { counts in
                    var exported: [String: Int] = [:]
                    for (s, n) in counts { exported[s.rawValue] = n }
                    return [
                        "exported_counts": exported,
                        "exported_counts_note": "Equal to the length of each top-level array. wifi/ble/uas = distinct devices; subghz = distinct captures.",
                        "live_at_export_counts": liveCounts,
                        "live_at_export_note": "Devices heard within the last \(liveWindow) s (Sub-GHz: captures still in the handheld RAM ring). A separate number from exported_counts.",
                        "handheld_log_total_available": handheld,
                        "handheld_log_records_ingested": ingested,
                        "handheld_log_note": "Records in the handheld flash log (/api/log/stats). Wi-Fi/BLE/UAS log one record per first sighting plus one per 5 min still present, so these exceed the distinct-device counts; for subghz each record is one capture.",
                    ]
                }
            }
        }.get()
    }

    func clearLocal() async {
        await db.run { $0.clear() }
        slots = [:]
        cursors = [:]
        liveSeen = [:]
        backfill = [:]
        rebuildAll()
    }

    // MARK: Sorted views

    private func rebuildAll() { rebuild(Set(ARIALogSource.allCases)) }

    private func rebuild(_ sources: Set<ARIALogSource>) {
        let cutoff = Date().addingTimeInterval(-Self.liveWindow)
        for source in sources {
            let prefix = source.rawValue + ":"
            let live = Set(liveSeen.filter { $0.key.hasPrefix(prefix) && $0.value >= cutoff }.keys.map { String($0.dropFirst(prefix.count)) })
            // In-range first, then newest first.
            let ordered = (slots[source] ?? [:]).sorted { a, b in
                let la = live.contains(a.key), lb = live.contains(b.key)
                return la != lb ? la : a.value.order > b.value.order
            }.map { $0.value.value }
            switch source {
            case .wifi: wifi = ordered.compactMap { item -> ARIAWiFiDevice? in
                if case .wifi(let v) = item { return v }
                return nil
            }
            case .ble: ble = ordered.compactMap { item -> ARIABLEDeviceRecord? in
                if case .ble(let v) = item { return v }
                return nil
            }
            case .subghz: subghz = ordered.compactMap { item -> ARIASubGHzCapture? in
                if case .subghz(let v) = item { return v }
                return nil
            }
            case .uas: uas = ordered.compactMap { item -> ARIAUASRecord? in
                if case .uas(let v) = item { return v }
                return nil
            }
            }
        }
    }
}
