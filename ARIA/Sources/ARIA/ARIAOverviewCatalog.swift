import Foundation

/// Overview-only projection. Original history, radio lists and exports stay verbatim.
struct ARIAOverviewCatalog: Codable {
    struct Record: Codable, Identifiable {
        let id: String
        var category: String
        var heardAt: Date?
        var raw: Data

        var fields: [String: Any] {
            (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
        }
        var label: String {
            let f = fields
            return ["uas_id", "ssid", "name", "mac", "address"].compactMap { f[$0] as? String }
                .first(where: { !$0.isEmpty }) ?? id
        }
    }

    struct Row: Identifiable {
        let id: String
        let records: [Record]
        let live: Int
        var total: Int { records.count }
        var priority: Bool { ["alpr_camera", "gunshot_detector", "drone"].contains(id) }
        var title: String {
            switch id {
            case "computer": return "Computers"
            case "phone": return "Phones"
            case "alpr_camera": return "ALPR cameras"
            case "gunshot_detector": return "Gunshot detectors"
            case "drone": return "Drones"
            case "subghz_decoded": return "Sub-GHz decoded"
            default: return id.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
        var icon: String {
            switch id {
            case "computer": return "laptopcomputer"
            case "phone": return "iphone"
            case "drone": return "airplane"
            case "alpr_camera", "other_camera": return "camera"
            case "gunshot_detector": return "waveform"
            case "subghz_decoded": return "chart.bar.fill"
            default: return "sensor"
            }
        }
    }

    private(set) var records: [String: Record] = [:]

    static func category(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !["", "unclassified", "unknown", "drone_control_candidate"].contains(value) else { return nil }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        return (value as? String).flatMap(Double.init)
    }

    // Firmware device last_seen_ms is an AGE; detections/UAS last_seen_ms is UPTIME.
    private static func heard(_ row: [String: Any], uptime: Double?, absolute: Bool, now: Date) -> Date? {
        let age: Double?
        if absolute {
            if let uptime, let last = number(row["last_seen_ms"] ?? row["timestamp_ms"] ?? row["ts_ms"]), uptime >= last {
                age = uptime - last
            } else { age = nil }
        } else { age = number(row["age_ms"] ?? row["last_seen_ms"]) }
        guard let age, age >= 0, age.isFinite else { return nil }
        return now.addingTimeInterval(-age / 1000)
    }

    mutating func insert(id: String, category: String?, row: [String: Any], heardAt: Date? = nil,
                         onlyIfMissing: Bool = false) {
        guard let category = Self.category(category), !id.isEmpty,
              !onlyIfMissing || records[id] == nil,
              let raw = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        let old = records[id]
        let latest = [old?.heardAt, heardAt].compactMap { $0 }.max()
        records[id] = Record(id: id, category: category, heardAt: latest, raw: raw)
    }

    mutating func ingestSession(_ data: Data, now: Date = Date()) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let firmware = root["firmware_response"] as? [String: Any] ?? root
        let session = firmware["session"] as? [String: Any] ?? firmware
        let uptime = Self.number(session["uptime_ms"])
        for radio in ["wifi", "ble"] {
            for row in root[radio] as? [[String: Any]] ?? [] {
                guard let mac = row["mac"] as? String ?? row["address"] as? String else { continue }
                insert(id: radio + ":" + mac.uppercased(), category: row["category"] as? String,
                       row: row, heardAt: Self.heard(row, uptime: uptime, absolute: false, now: now))
            }
        }
        for row in root["subghz"] as? [[String: Any]] ?? [] {
            guard Self.isDecoded(row), let seq = Self.number(row["sequence"]) else { continue }
            let boot = Self.number(row["boot"] ?? row["boot_id"]) ?? 0
            insert(id: "subghz:\(Int(seq))-\(Int(boot))", category: "subghz_decoded", row: row,
                   heardAt: Self.heard(row, uptime: uptime, absolute: true, now: now))
        }
    }

    static func isDecoded(_ row: [String: Any]) -> Bool {
        let decode = row["decode"] as? [String: Any] ?? [:]
        let state = (decode["decoded_status"] as? String ?? row["decode_state"] as? String ?? "").uppercased()
        // Missing, ERROR, UNKNOWN and INCOMPLETE are not successful decodes.
        return ["DECODED", "VERIFIED", "VALID", "VALIDATED"].contains(state)
    }

    mutating func ingestCapabilities(_ root: [String: Any], now: Date = Date()) {
        let uptime = Self.number(root["uptime_ms"])
        for row in root["detections"] as? [[String: Any]] ?? [] {
            guard let mac = row["mac"] as? String,
                  let radio = row["radio"] as? String, ["wifi", "ble"].contains(radio) else { continue }
            insert(id: radio + ":" + mac.uppercased(), category: row["category"] as? String,
                   row: row, heardAt: Self.heard(row, uptime: uptime, absolute: true, now: now))
        }
        let uas = root["uas"] as? [String: Any] ?? [:]
        for row in uas["observations"] as? [[String: Any]] ?? [] {
            guard row["validation"] as? Bool == true,
                  row["classification"] as? String == "VALIDATED_REMOTE_ID",
                  let id = row["uas_id"] as? String, !id.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            insert(id: "uas:" + id, category: "drone", row: row,
                   heardAt: Self.heard(row, uptime: uptime, absolute: true, now: now))
        }
    }

    func rows(now: Date = Date(), connected: Bool) -> [Row] {
        let priority = ["alpr_camera", "gunshot_detector", "drone"]
        return Dictionary(grouping: records.values, by: \.category).map { key, records in
            Row(id: key, records: records.sorted { $0.id < $1.id }, live: connected ? records.filter {
                guard let heard = $0.heardAt else { return false }
                return now.timeIntervalSince(heard) >= 0 && now.timeIntervalSince(heard) <= 60
            }.count : 0)
        }.sorted {
            let a = priority.firstIndex(of: $0.id) ?? priority.count
            let b = priority.firstIndex(of: $1.id) ?? priority.count
            return a == b ? $0.title < $1.title : a < b
        }
    }
}
