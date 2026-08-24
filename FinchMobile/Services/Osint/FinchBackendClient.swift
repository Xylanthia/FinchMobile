import Foundation

enum FinchBackendClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 240
        config.httpAdditionalHeaders = [
            "User-Agent": "FinchMobile/3.2 (Finch backend client)",
            "Accept": "application/json"
        ]
        return URLSession(configuration: config)
    }()

    struct BackendFailure: Error {
        var message: String
        var statusCode: Int?
    }

    static func normalizedBaseURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }
        guard var parts = URLComponents(string: trimmed),
              let host = parts.host, !host.isEmpty else { return nil }
        if parts.scheme?.lowercased() != "http" && parts.scheme?.lowercased() != "https" {
            return nil
        }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.query = nil
        parts.fragment = nil
        if parts.port == nil {
            parts.port = parts.scheme == "https" ? 443 : 80
        }
        return parts.url
    }

    static func apiType(for kind: PipelineKind) -> String {
        switch kind {
        case .property: return "address"
        case .plate: return "plate"
        default: return "auto"
        }
    }

    static func backendSeedKind(for seed: CaseSeed) -> String {
        let q = seed.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if InputRouter.isETH(q) { return "wallet" }
        if InputRouter.isEmail(q) { return "email" }
        if InputRouter.isPhone(q) { return "phone" }
        if InputRouter.isMAC(q) { return "mac" }
        if InputRouter.isPublicIPv4(q) || InputRouter.isPrivateIP(q) { return "ip" }
        if InputRouter.isDomain(q) { return "domain" }
        if InputRouter.isURL(q) { return "url" }
        if InputRouter.isVIN(q) || InputRouter.isPlate(q) { return "plate" }
        if InputRouter.looksLikeAddress(q) { return "address" }
        if InputRouter.isUsername(q) { return "username" }
        return "name"
    }

    static func pipeline(for backendKind: String, value: String) -> PipelineKind {
        switch backendKind {
        case "address", "property", "address_dossier": return .property
        case "plate", "vehicle": return .plate
        case "domain", "ip", "url", "vuln", "cert", "infra", "device", "camera", "feed", "breach":
            return .cyber
        case "contract", "wallet": return .web3
        default: return InputRouter.classify(value)
        }
    }

    static func caseContextJSON(seeds: [CaseSeed], excluding query: String) -> String? {
        let qLower = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prior = seeds
            .filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != qLower }
            .prefix(24)
            .map { ["kind": backendSeedKind(for: $0), "value": $0.value] }
        guard !prior.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: prior) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func run(
        query: String,
        kind: PipelineKind,
        caseSeeds: [CaseSeed],
        settings: SettingsStore
    ) async -> OsintReport? {
        do {
            let root = try await fetchRunJSON(query: query, kind: kind, caseSeeds: caseSeeds, settings: settings)
            return mapReport(root, query: query, kind: kind, started: Date())
        } catch {
            return nil
        }
    }

    static func runOrExplainFailure(
        query: String,
        kind: PipelineKind,
        caseSeeds: [CaseSeed],
        settings: SettingsStore
    ) async -> Result<OsintReport, BackendFailure> {
        do {
            let root = try await fetchRunJSON(query: query, kind: kind, caseSeeds: caseSeeds, settings: settings)
            return .success(mapReport(root, query: query, kind: kind, started: Date()))
        } catch let failure as BackendFailure {
            return .failure(failure)
        } catch {
            return .failure(BackendFailure(message: error.localizedDescription, statusCode: nil))
        }
    }

    static func failureReport(query: String, kind: PipelineKind, failure: BackendFailure, backendURL: String) -> OsintReport {
        OsintReport(
            query: query,
            pipeline: kind,
            brief: [
                "Finch backend unreachable — web app parity requires your PC backend.",
                failure.message,
                "On your PC: python -m backend serve --host 0.0.0.0 --port 8765",
                "Settings → Backend URL → http://YOUR_PC_IP:8765 (same Wi‑Fi as phone).",
                "Configured: \(backendURL)"
            ],
            findings: [],
            actions: [],
            startedAt: Date(),
            finishedAt: Date()
        )
    }

    private static func fetchRunJSON(
        query: String,
        kind: PipelineKind,
        caseSeeds: [CaseSeed],
        settings: SettingsStore
    ) async throws -> [String: Any] {
        guard let base = normalizedBaseURL(settings.finchBackendURL) else {
            throw BackendFailure(message: "Invalid backend URL in Settings.", statusCode: nil)
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            throw BackendFailure(message: "Empty query.", statusCode: nil)
        }
        guard let endpoint = URL(string: "/api/run", relativeTo: base) else {
            throw BackendFailure(message: "Could not build /api/run URL.", statusCode: nil)
        }

        var body: [String: Any] = [
            "query": q,
            "type": apiType(for: kind),
            "route": "osint",
            "enrich_fabric": false
        ]
        if let ctx = caseContextJSON(seeds: caseSeeds, excluding: q) {
            body["case_context"] = ctx
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let snippet = String(data: data.prefix(240), encoding: .utf8) ?? ""
            throw BackendFailure(message: "HTTP \(code)\(snippet.isEmpty ? "" : " — \(snippet)")", statusCode: code)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackendFailure(message: "Backend returned non-JSON.", statusCode: code)
        }
        return root
    }

    private static func mapReport(
        _ root: [String: Any],
        query: String,
        kind: PipelineKind,
        started: Date
    ) -> OsintReport {
        let rawRows = collectFindingRows(from: root)
        var findings: [OsintFinding] = []
        var seen = Set<String>()
        for row in rawRows {
            for expanded in expandFindingRow(row) {
                let hit = mapFinding(expanded)
                let key = "\(hit.source)|\(hit.kind)|\(hit.value)|\(hit.url ?? "")"
                if seen.contains(key) { continue }
                seen.insert(key)
                findings.append(hit)
            }
        }
        findings.sort(by: findingSort)

        var brief: [String] = []
        if let intel = root["intel"] as? [String: Any] {
            for item in intel["brief"] as? [[String: Any]] ?? [] {
                if let text = item["text"] as? String, !text.isEmpty {
                    brief.append(text)
                }
            }
        }
        if brief.isEmpty, let target = root["target"] as? String {
            brief.append("Finch backend run complete for \(target).")
        }

        var actions: [OsintAction] = []
        if let intel = root["intel"] as? [String: Any] {
            for item in intel["actions"] as? [[String: Any]] ?? [] {
                if let action = mapAction(item) { actions.append(action) }
            }
        }
        if actions.isEmpty {
            for item in root["links"] as? [[String: Any]] ?? [] {
                if let action = mapLinkAction(item) { actions.append(action) }
            }
        }

        let total = root["total_findings"] as? Int ?? findings.count
        brief.insert("Finch desktop backend · \(total) findings (same engine as web app)", at: 0)

        return OsintReport(
            query: query,
            pipeline: kind,
            brief: brief,
            findings: findings,
            actions: actions,
            startedAt: started,
            finishedAt: Date()
        )
    }

    private static func collectFindingRows(from root: [String: Any]) -> [[String: Any]] {
        var rows = root["findings"] as? [[String: Any]] ?? []
        if let dossier = root["dossier"] as? [String: Any] {
            for (_, value) in dossier {
                guard let items = value as? [[String: Any]] else { continue }
                rows.append(contentsOf: items)
            }
        }
        return rows
    }

    private static func expandFindingRow(_ row: [String: Any]) -> [[String: Any]] {
        guard (row["kind"] as? String) == "address_dossier",
              let meta = row["meta"] as? [String: Any],
              let blob = meta["address_dossier"] as? [String: Any] else {
            return [row]
        }

        var extras: [[String: Any]] = []
        let addr = (blob["standardized_address"] as? String) ?? (row["value"] as? String) ?? ""

        let summary = propertySummary(from: blob["property_details"] as? [String: Any], county: blob["county"] as? String)
        if !summary.isEmpty {
            extras.append([
                "source": "reverse_address.property",
                "kind": "property",
                "value": summary,
                "relevance": "relevant",
                "confidence": 0.9,
                "meta": ["role": "public_record", "reverse_address": true]
            ])
        }

        for owner in blob["owners"] as? [[String: Any]] ?? [] {
            guard let name = owner["name"] as? String, !name.isEmpty else { continue }
            extras.append([
                "source": owner["source"] as? String ?? "reverse_address.owner",
                "kind": "name",
                "value": name,
                "url": owner["url"] as? String ?? "",
                "relevance": "relevant",
                "confidence": 0.92,
                "meta": [
                    "role": "owner",
                    "from_source": owner["source"] as? String ?? "assessor",
                    "address": addr,
                    "reverse_address": true,
                    "spawn_identity": true
                ]
            ])
        }

        for occ in blob["occupants_possible"] as? [[String: Any]] ?? [] {
            guard let name = occ["name"] as? String, !name.isEmpty else { continue }
            extras.append([
                "source": occ["source"] as? String ?? "reverse_address.occupant",
                "kind": "name",
                "value": name,
                "url": occ["url"] as? String ?? "",
                "relevance": "relevant",
                "confidence": 0.7,
                "meta": [
                    "role": "occupant_possible",
                    "from_source": occ["source"] as? String ?? "",
                    "address": addr,
                    "reverse_address": true
                ]
            ])
        }

        for phone in blob["phone_numbers"] as? [[String: Any]] ?? [] {
            guard let num = phone["phone"] as? String, !num.isEmpty else { continue }
            extras.append([
                "source": phone["source"] as? String ?? "reverse_address.phone",
                "kind": "phone",
                "value": num,
                "url": phone["url"] as? String ?? "",
                "relevance": "relevant",
                "confidence": 0.75,
                "meta": [
                    "from_source": phone["source"] as? String ?? "",
                    "address": addr,
                    "reverse_address": true
                ]
            ])
        }

        for biz in blob["businesses_at_address"] as? [[String: Any]] ?? [] {
            guard let name = biz["name"] as? String, !name.isEmpty else { continue }
            extras.append([
                "source": biz["source"] as? String ?? "reverse_address.business",
                "kind": "business",
                "value": name,
                "url": biz["url"] as? String ?? "",
                "relevance": "relevant",
                "confidence": 0.65,
                "meta": ["address": addr, "reverse_address": true]
            ])
        }

        for url in blob["source_urls"] as? [String] ?? [] where url.hasPrefix("http") {
            extras.append([
                "source": "reverse_address.pivot",
                "kind": "url",
                "value": "County / assessor source",
                "url": url,
                "relevance": "relevant",
                "confidence": 0.6,
                "meta": ["reverse_address": true]
            ])
        }

        return [row] + extras
    }

    private static func propertySummary(from details: [String: Any]?, county: String?) -> String {
        guard let details else { return "" }
        var bits: [String] = []
        if let owner = details["owner"] as? String, !owner.isEmpty { bits.append("Owner: \(owner)") }
        if let val = details["assessed_value"] { bits.append("Assessed: $\(val)") }
        if let tax = details["tax_base"] { bits.append("Tax base: $\(tax)") }
        if let year = details["year_built"] { bits.append("Built: \(year)") }
        if let sqft = details["sqft"] { bits.append("\(sqft) sqft") }
        if let pin = details["pin"] as? String, !pin.isEmpty { bits.append("PIN: \(pin)") }
        if let block = details["block_lot"] as? String, !block.isEmpty { bits.append("Block/Lot: \(block)") }
        if let mail = details["mailing_address"] as? String, !mail.isEmpty { bits.append("Mail: \(mail)") }
        if let hood = details["neighborhood"] as? String, !hood.isEmpty { bits.append(hood) }
        if let county, !county.isEmpty { bits.append("\(county) assessor/GIS") }
        if bits.isEmpty, let summary = details["summary"] as? String { return summary }
        return bits.joined(separator: " · ")
    }

    private static func mapFinding(_ row: [String: Any]) -> OsintFinding {
        let source = row["source"] as? String ?? "finch"
        let kind = row["kind"] as? String ?? "note"
        let value = row["value"] as? String ?? ""
        let relevanceRaw = (row["relevance"] as? String ?? "").lowercased()
        let confidence = row["confidence"] as? Double ?? 0
        let relevance: String
        if relevanceRaw == "relevant" || confidence >= 0.7 {
            relevance = "signal"
        } else {
            relevance = "static"
        }
        let url = (row["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = formatMetaNote(row["meta"] as? [String: Any] ?? [:], kind: kind, source: source)
        return OsintFinding(
            source: source,
            kind: kind,
            value: value,
            relevance: relevance,
            url: (url?.isEmpty ?? true) ? nil : url,
            note: note
        )
    }

    private static func formatMetaNote(_ meta: [String: Any], kind: String, source: String) -> String {
        var parts: [String] = []
        if let role = meta["role"] as? String, !role.isEmpty { parts.append(role.replacingOccurrences(of: "_", with: " ")) }
        if let src = meta["from_source"] as? String, !src.isEmpty { parts.append(src) }
        if let county = meta["county"] as? String, !county.isEmpty { parts.append(county) }
        if let city = meta["city"] as? String, let state = meta["state"] as? String {
            parts.append("\(city), \(state)")
        }
        if let pd = meta["property_details"] as? [String: Any] {
            let summary = propertySummary(from: pd, county: meta["county"] as? String)
            if !summary.isEmpty { parts.append(summary) }
        }
        if kind == "property", let owner = meta["owner"] as? String, !owner.isEmpty {
            parts.append("owner \(owner)")
        }
        if parts.isEmpty, let rail = meta["rail"] as? String { parts.append(rail) }
        if parts.isEmpty, !source.isEmpty { parts.append(source) }
        return parts.prefix(6).joined(separator: " · ")
    }

    private static func findingSort(_ lhs: OsintFinding, _ rhs: OsintFinding) -> Bool {
        func rank(_ f: OsintFinding) -> Int {
            if f.kind == "address_dossier" { return 0 }
            if f.kind == "name", f.note.contains("owner") { return 1 }
            if f.kind == "property" { return 2 }
            if f.kind == "phone" { return 3 }
            if f.kind == "name" { return 4 }
            if f.kind == "address" { return 5 }
            return 10
        }
        let lr = rank(lhs), rr = rank(rhs)
        if lr != rr { return lr < rr }
        return lhs.value < rhs.value
    }

    private static func mapAction(_ row: [String: Any]) -> OsintAction? {
        guard let title = row["title"] as? String, !title.isEmpty else { return nil }
        let value = (row["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind = row["kind"] as? String ?? "note"
        let seed = value.isEmpty ? title : value
        return OsintAction(
            title: title,
            seed: seed,
            pipeline: pipeline(for: kind, value: seed)
        )
    }

    private static func mapLinkAction(_ row: [String: Any]) -> OsintAction? {
        guard let url = row["url"] as? String, !url.isEmpty else { return nil }
        let label = row["label"] as? String ?? row["value"] as? String ?? url
        let kind = row["kind"] as? String ?? "url"
        return OsintAction(
            title: label,
            seed: label,
            pipeline: pipeline(for: kind, value: label)
        )
    }
}
