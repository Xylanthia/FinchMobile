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
        guard let base = normalizedBaseURL(settings.finchBackendURL) else { return nil }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        guard let endpoint = URL(string: "/api/run", relativeTo: base) else { return nil }
        var body: [String: Any] = [
            "query": q,
            "type": apiType(for: kind),
            "route": "osint",
            "enrich_fabric": false
        ]
        if let ctx = caseContextJSON(seeds: caseSeeds, excluding: q) {
            body["case_context"] = ctx
        }

        let started = Date()
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code) else { return nil }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return mapReport(root, query: q, kind: kind, started: started)
        } catch {
            return nil
        }
    }

    private static func mapReport(
        _ root: [String: Any],
        query: String,
        kind: PipelineKind,
        started: Date
    ) -> OsintReport {
        let findingsRaw = root["findings"] as? [[String: Any]] ?? []
        let findings = findingsRaw.map { mapFinding($0) }

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
        if !brief.isEmpty {
            brief.insert("Finch desktop backend · \(total) findings", at: 0)
        }

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
        let url = row["url"] as? String
        var note = ""
        if let meta = row["meta"] as? [String: Any], !meta.isEmpty {
            if let role = meta["role"] as? String { note = role }
            else if let city = meta["city"] as? String, let state = meta["state"] as? String {
                note = "\(city), \(state)"
            }
        }
        return OsintFinding(
            source: source,
            kind: kind,
            value: value,
            relevance: relevance,
            url: url?.isEmpty == true ? nil : url,
            note: note
        )
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
