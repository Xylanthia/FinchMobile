import Foundation
import Observation
import CryptoKit
import CoreLocation

enum OsintHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        config.httpAdditionalHeaders = [
            "User-Agent": "FinchMobile/3.0 (authorized OSINT; on-device)",
            "Accept": "application/json, text/plain, */*"
        ]
        return URLSession(configuration: config)
    }()

    static func get(url: URL, headers: [String: String] = [:]) async -> (Int, Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (code, data)
        } catch {
            return (0, Data())
        }
    }

    static func postJSON(url: URL, body: [String: Any]) async -> (Int, Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (code, data)
        } catch {
            return (0, Data())
        }
    }

    static func jsonObject(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }
}

@Observable
@MainActor
final class OsintEngine {
    var report: OsintReport?
    var isRunning: Bool = false
    var progressText: String = ""
    private var runTask: Task<Void, Never>?

    func reset() {
        runTask?.cancel()
        report = nil
        isRunning = false
        progressText = ""
    }

    func run(query: String, kind: PipelineKind, settings: SettingsStore) {
        runTask?.cancel()
        runTask = Task { await execute(query: query, kind: kind, settings: settings) }
    }

    private func execute(query: String, kind: PipelineKind, settings: SettingsStore) async {
        isRunning = true
        progressText = "Engage → \(kind.label)"
        report = nil
        let started = Date()
        var findings: [OsintFinding] = []
        var actions: [OsintAction] = []
        var brief: [String] = []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
            case .identity:
                progressText = "Identity rails…"
                let bundle = await identity(q, settings: settings)
                findings = bundle.0
                actions = bundle.1
                brief = bundle.2
            case .property:
                progressText = "Property rails…"
                let bundle = await property(q)
                findings = bundle.0
                actions = bundle.1
                brief = bundle.2
            case .plate:
                progressText = "Plate rails…"
                let bundle = await plate(q)
                findings = bundle.0
                actions = bundle.1
                brief = bundle.2
            case .cyber:
                progressText = "Cyber rails…"
                let bundle = await cyber(q, settings: settings)
                findings = bundle.0
                actions = bundle.1
                brief = bundle.2
            case .web3:
                progressText = "Web3 rails…"
                let bundle = await web3(q, settings: settings)
                findings = bundle.0
                actions = bundle.1
                brief = bundle.2
            default:
                brief = ["This seed routes to Glass or Nearby, not the OSINT lattice."]
        }

        if findings.isEmpty && brief.isEmpty {
            brief = ["No public hits. Try another seed, or add API keys in Settings."]
        }
        report = OsintReport(
            query: q,
            pipeline: kind,
            brief: brief,
            findings: findings,
            actions: actions,
            startedAt: started,
            finishedAt: Date()
        )
        isRunning = false
        progressText = "Done · \(findings.count) findings"
    }

    // MARK: - Identity

    private func identity(_ q: String, settings: SettingsStore) async -> ([OsintFinding], [OsintAction], [String]) {
        var findings: [OsintFinding] = []
        var actions: [OsintAction] = []
        var brief: [String] = []
        let lower = q.lowercased()

        if InputRouter.isEmail(q) {
            brief.append("Email seed — public reputation, mail host, optional HIBP.")
            await emailRep(q, into: &findings)
            await gravatar(q, into: &findings)
            if !settings.hibpApiKey.isEmpty {
                await hibp(q, key: settings.hibpApiKey, into: &findings)
            } else {
                findings.append(OsintFinding(
                    source: "hibp",
                    kind: "note",
                    value: "Have I Been Pwned skipped — add an API key in Settings.",
                    relevance: "static"
                ))
            }
            if let at = q.split(separator: "@").last {
                let domain = String(at)
                actions.append(OsintAction(title: "Engage domain \(domain)", seed: domain, pipeline: .cyber))
            }
            let local = String(q.split(separator: "@").first ?? "")
            if local.count >= 3 {
                actions.append(OsintAction(title: "Check handle @\(local)", seed: "@\(local)", pipeline: .identity))
            }
        } else if InputRouter.isPhone(q) {
            let digits = InputRouter.digitsOnly(q)
            brief.append("Phone seed — E.164 format only on-device. Carrier APIs need a key.")
            findings.append(OsintFinding(
                source: "phone",
                kind: "phone",
                value: InputRouter.formatNANP(digits),
                relevance: "signal",
                note: "Normalized. No CNAM without a paid key."
            ))
            findings.append(OsintFinding(
                source: "dork",
                kind: "url",
                value: "Public web mentions",
                relevance: "static",
                url: "https://duckduckgo.com/?q=%22\(digits)%22"
            ))
        } else if InputRouter.isUsername(q) {
            let handle = q.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
            brief.append("Username seed — presence checks on public profile endpoints. Exact-seed: no invented handles.")
            await usernameSweep(handle, into: &findings)
        } else if InputRouter.isMAC(q) {
            brief.append("MAC seed — OUI vendor from bundled table if present.")
            findings.append(OsintFinding(source: "mac", kind: "mac", value: q.uppercased(), relevance: "signal"))
        } else {
            brief.append("Name seed — public catalogs only. No invented usernames from a bare name.")
            await nameSweep(q, into: &findings)
            actions.append(OsintAction(title: "Search as username @\(slug(q))", seed: "@\(slug(q))", pipeline: .identity))
        }

        _ = lower
        return (findings, actions, brief)
    }

    private func emailRep(_ email: String, into findings: inout [OsintFinding]) async {
        guard let url = URL(string: "https://emailrep.io/\(email)") else { return }
        let (code, data) = await OsintHTTP.get(url: url)
        guard code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any] else {
            findings.append(OsintFinding(source: "emailrep", kind: "note", value: "EmailRep returned \(code)", relevance: "static"))
            return
        }
        if let reputation = obj["reputation"] as? String {
            findings.append(OsintFinding(source: "emailrep", kind: "email", value: "reputation \(reputation)", relevance: "signal"))
        }
        if let suspicious = obj["suspicious"] as? Bool, suspicious {
            findings.append(OsintFinding(source: "emailrep", kind: "email", value: "marked suspicious", relevance: "signal"))
        }
        if let details = obj["details"] as? [String: Any] {
            if let provider = details["mail_provider"] as? String {
                findings.append(OsintFinding(source: "emailrep", kind: "infra", value: provider, relevance: "static"))
            }
            if let profiles = details["profiles"] as? [String] {
                for p in profiles.prefix(12) {
                    findings.append(OsintFinding(source: "emailrep", kind: "account", value: p, relevance: "signal"))
                }
            }
        }
    }

    private func gravatar(_ email: String, into findings: inout [OsintFinding]) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = Insecure.MD5.hash(data: Data(trimmed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard let url = URL(string: "https://www.gravatar.com/\(hex).json") else { return }
        let (code, data) = await OsintHTTP.get(url: url)
        if code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
           let entry = (obj["entry"] as? [[String: Any]])?.first {
            let display = entry["displayName"] as? String ?? "Gravatar profile"
            let profileUrl = entry["profileUrl"] as? String
            findings.append(OsintFinding(
                source: "gravatar",
                kind: "account",
                value: display,
                relevance: "signal",
                url: profileUrl
            ))
        }
    }

    private func hibp(_ email: String, key: String, into findings: inout [OsintFinding]) async {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
        guard let url = URL(string: "https://haveibeenpwned.com/api/v3/breachedaccount/\(encoded)?truncateResponse=false") else { return }
        let (code, data) = await OsintHTTP.get(url: url, headers: [
            "hibp-api-key": key,
            "user-agent": "FinchMobile"
        ])
        if code == 404 {
            findings.append(OsintFinding(source: "hibp", kind: "breach", value: "No breaches on file", relevance: "static"))
            return
        }
        guard code == 200, let arr = OsintHTTP.jsonObject(data) as? [[String: Any]] else {
            findings.append(OsintFinding(source: "hibp", kind: "note", value: "HIBP HTTP \(code)", relevance: "static"))
            return
        }
        for row in arr.prefix(20) {
            let name = row["Name"] as? String ?? row["Title"] as? String ?? "breach"
            findings.append(OsintFinding(source: "hibp", kind: "breach", value: name, relevance: "signal"))
        }
    }

    private func usernameSweep(_ handle: String, into findings: inout [OsintFinding]) async {
        let checks: [(String, String)] = [
            ("GitHub", "https://api.github.com/users/\(handle)"),
            ("GitLab", "https://gitlab.com/api/v4/users?username=\(handle)"),
            ("Reddit", "https://www.reddit.com/user/\(handle)/about.json"),
            ("HackerOne", "https://hackerone.com/\(handle)"),
            ("Keybase", "https://keybase.io/_/api/1.0/user/lookup.json?username=\(handle)")
        ]
        await withTaskGroup(of: OsintFinding?.self) { group in
            for (name, raw) in checks {
                group.addTask {
                    guard let url = URL(string: raw) else { return nil }
                    let (code, data) = await OsintHTTP.get(url: url)
                    if name == "GitHub", code == 200,
                       let obj = OsintHTTP.jsonObject(data) as? [String: Any],
                       let html = obj["html_url"] as? String {
                        let bio = obj["name"] as? String ?? handle
                        return OsintFinding(source: "github", kind: "account", value: bio, relevance: "signal", url: html)
                    }
                    if name == "Keybase", code == 200,
                       let obj = OsintHTTP.jsonObject(data) as? [String: Any],
                       let status = obj["status"] as? [String: Any],
                       (status["code"] as? Int) == 0 {
                        return OsintFinding(source: "keybase", kind: "account", value: handle, relevance: "signal", url: "https://keybase.io/\(handle)")
                    }
                    if name == "Reddit", code == 200 {
                        return OsintFinding(source: "reddit", kind: "account", value: "u/\(handle)", relevance: "signal", url: "https://www.reddit.com/user/\(handle)")
                    }
                    if name == "GitLab", code == 200,
                       let arr = OsintHTTP.jsonObject(data) as? [[String: Any]], !arr.isEmpty {
                        return OsintFinding(source: "gitlab", kind: "account", value: handle, relevance: "signal", url: "https://gitlab.com/\(handle)")
                    }
                    if name == "HackerOne", code == 200, data.count > 200 {
                        return OsintFinding(source: "hackerone", kind: "account", value: handle, relevance: "signal", url: raw)
                    }
                    return nil
                }
            }
            for await hit in group {
                if let hit { findings.append(hit) }
            }
        }
        if findings.filter({ $0.kind == "account" }).isEmpty {
            findings.append(OsintFinding(source: "username", kind: "note", value: "No public profile hits for \(handle)", relevance: "static"))
        }
    }

    private func nameSweep(_ name: String, into findings: inout [OsintFinding]) async {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        if let url = URL(string: "https://en.wikipedia.org/w/api.php?action=opensearch&search=\(encoded)&limit=5&namespace=0&format=json") {
            let (code, data) = await OsintHTTP.get(url: url)
            if code == 200, let arr = OsintHTTP.jsonObject(data) as? [Any],
               arr.count >= 4, let titles = arr[1] as? [String], let links = arr[3] as? [String] {
                for (idx, title) in titles.prefix(5).enumerated() {
                    let link = idx < links.count ? links[idx] : nil
                    findings.append(OsintFinding(source: "wikipedia", kind: "note", value: title, relevance: "static", url: link))
                }
            }
        }
        if let url = URL(string: "https://www.courtlistener.com/api/rest/v4/search/?q=\(encoded)&type=o&page_size=5") {
            let (code, data) = await OsintHTTP.get(url: url)
            if code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
               let results = obj["results"] as? [[String: Any]] {
                for row in results.prefix(5) {
                    let caseName = row["caseName"] as? String ?? row["caseNameFull"] as? String ?? "opinion"
                    let abs = row["absolute_url"] as? String
                    let href = abs.map { $0.hasPrefix("http") ? $0 : "https://www.courtlistener.com\($0)" }
                    findings.append(OsintFinding(source: "courtlistener", kind: "record", value: caseName, relevance: "signal", url: href))
                }
            }
        }
        if let url = URL(string: "https://api.open.fec.gov/v1/names/?q=\(encoded)&api_key=DEMO_KEY") {
            let (code, data) = await OsintHTTP.get(url: url)
            if code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
               let results = obj["results"] as? [[String: Any]] {
                for row in results.prefix(5) {
                    let n = row["name"] as? String ?? "FEC name"
                    findings.append(OsintFinding(source: "fec", kind: "fec_contribution", value: n, relevance: "static"))
                }
            }
        }
        if let url = URL(string: "https://api.opensanctions.org/search/default?q=\(encoded)&limit=5") {
            let (code, data) = await OsintHTTP.get(url: url)
            if code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
               let results = obj["results"] as? [[String: Any]] {
                for row in results.prefix(5) {
                    let n = row["caption"] as? String ?? "sanction hit"
                    findings.append(OsintFinding(source: "opensanctions", kind: "record", value: n, relevance: "signal"))
                }
            }
        }
        findings.append(OsintFinding(
            source: "doctrine",
            kind: "note",
            value: "Exact-seed — no invented social handles from “\(name)”. Engage a real @username if you have one.",
            relevance: "static"
        ))
    }

    // MARK: - Property

    private func property(_ q: String) async -> ([OsintFinding], [OsintAction], [String]) {
        var findings: [OsintFinding] = []
        var actions: [OsintAction] = []
        var brief: [String] = ["Street address — geocode + Census. County assessor still needs a tap-through."]
        let geo = CLGeocoder()
        do {
            let marks = try await geo.geocodeAddressString(q)
            if let mark = marks.first {
                let loc = mark.location
                let lat = loc?.coordinate.latitude ?? 0
                let lon = loc?.coordinate.longitude ?? 0
                if abs(lat) < 0.0001 && abs(lon) < 0.0001 {
                    findings.append(OsintFinding(source: "geocode", kind: "note", value: "Location unavailable (null-island)", relevance: "static"))
                } else {
                    findings.append(OsintFinding(
                        source: "geocode",
                        kind: "geo",
                        value: String(format: "%.5f, %.5f", lat, lon),
                        relevance: "signal",
                        note: [mark.locality, mark.administrativeArea, mark.postalCode].compactMap { $0 }.joined(separator: ", ")
                    ))
                }
                if let city = mark.locality, let state = mark.administrativeArea {
                    findings.append(OsintFinding(source: "geocode", kind: "property", value: "\(city), \(state)", relevance: "signal"))
                }
            }
        } catch {
            findings.append(OsintFinding(source: "geocode", kind: "note", value: error.localizedDescription, relevance: "static"))
        }

        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let url = URL(string: "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?address=\(encoded)&benchmark=Public_AR_Current&format=json") {
            let (code, data) = await OsintHTTP.get(url: url)
            if code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
               let result = obj["result"] as? [String: Any],
               let matches = result["addressMatches"] as? [[String: Any]],
               let first = matches.first {
                let matched = first["matchedAddress"] as? String ?? q
                findings.append(OsintFinding(source: "census", kind: "property", value: matched, relevance: "signal"))
                if let coords = first["coordinates"] as? [String: Any] {
                    let x = coords["x"] as? Double ?? 0
                    let y = coords["y"] as? Double ?? 0
                    findings.append(OsintFinding(source: "census", kind: "geo", value: String(format: "%.5f, %.5f", y, x), relevance: "static"))
                }
            }
        }
        if let url = URL(string: "https://nominatim.openstreetmap.org/search?q=\(encoded)&format=json&limit=1") {
            let (code, data) = await OsintHTTP.get(url: url)
            if code == 200, let arr = OsintHTTP.jsonObject(data) as? [[String: Any]], let first = arr.first {
                let display = first["display_name"] as? String ?? "Nominatim"
                findings.append(OsintFinding(source: "nominatim", kind: "property", value: display, relevance: "static"))
            }
        }
        actions.append(OsintAction(title: "Open assessor search", seed: q, pipeline: .property))
        return (findings, actions, brief)
    }

    // MARK: - Plate

    private func plate(_ q: String) async -> ([OsintFinding], [OsintAction], [String]) {
        var findings: [OsintFinding] = []
        let actions: [OsintAction] = []
        var brief: [String] = ["Plate intelligence — public listings and NHTSA VIN decode. No DMV."]
        let token = q.replacingOccurrences(of: " ", with: "").uppercased()
        if InputRouter.isVIN(token) {
            brief.append("17-character VIN — decoding via NHTSA vPIC.")
            if let url = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/\(token)?format=json") {
                let (code, data) = await OsintHTTP.get(url: url)
                if code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
                   let results = obj["Results"] as? [[String: Any]], let row = results.first {
                    let make = row["Make"] as? String ?? ""
                    let model = row["Model"] as? String ?? ""
                    let year = row["ModelYear"] as? String ?? ""
                    let vehicle = [year, make, model].filter { !$0.isEmpty }.joined(separator: " ")
                    if !vehicle.isEmpty {
                        findings.append(OsintFinding(source: "nhtsa", kind: "vehicle", value: vehicle, relevance: "signal"))
                    }
                    if let plant = row["PlantCity"] as? String, !plant.isEmpty {
                        findings.append(OsintFinding(source: "nhtsa", kind: "note", value: "Plant \(plant)", relevance: "static"))
                    }
                }
            }
        } else {
            findings.append(OsintFinding(
                source: "plate",
                kind: "plate",
                value: token,
                relevance: "signal",
                note: "No VIN on this seed. Public classifieds only — no DMV lookup."
            ))
            let qenc = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            findings.append(OsintFinding(
                source: "dork",
                kind: "url",
                value: "Public web mentions of plate",
                relevance: "static",
                url: "https://duckduckgo.com/?q=%22\(qenc)%22+vin+OR+for+sale"
            ))
        }
        return (findings, actions, brief)
    }

    // MARK: - Cyber

    private func cyber(_ q: String, settings: SettingsStore) async -> ([OsintFinding], [OsintAction], [String]) {
        var findings: [OsintFinding] = []
        var actions: [OsintAction] = []
        var brief: [String] = ["Cyber — DNS-over-HTTPS, RDAP, CT, InternetDB."]
        var host = q
        if let url = URL(string: q.hasPrefix("http") ? q : "https://\(q)"), let h = url.host {
            host = h
        }
        host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        await doh(host, type: "A", into: &findings)
        await doh(host, type: "AAAA", into: &findings)
        await doh(host, type: "MX", into: &findings)
        await doh(host, type: "TXT", into: &findings)
        await rdapDomain(host, into: &findings)
        await crtsh(host, into: &findings)

        if InputRouter.isIPv4(host) {
            await internetDB(host, into: &findings)
            await rdapIP(host, into: &findings)
            if !settings.shodanApiKey.isEmpty {
                await shodanHost(host, key: settings.shodanApiKey, into: &findings)
            }
        } else {
            // resolve A then internetdb
            if let ip = findings.first(where: { $0.source == "doh" && $0.kind == "ip" })?.value {
                await internetDB(ip, into: &findings)
                actions.append(OsintAction(title: "Engage IP \(ip)", seed: ip, pipeline: .cyber))
            }
        }
        return (findings, actions, brief)
    }

    private func doh(_ name: String, type: String, into findings: inout [OsintFinding]) async {
        var comps = URLComponents(string: "https://cloudflare-dns.com/dns-query")
        comps?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "type", value: type)
        ]
        guard let url = comps?.url else { return }
        let (code, data) = await OsintHTTP.get(url: url, headers: ["Accept": "application/dns-json"])
        guard code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
              let answers = obj["Answer"] as? [[String: Any]] else { return }
        for ans in answers.prefix(8) {
            let dataStr = ans["data"] as? String ?? ""
            let kind = type == "A" || type == "AAAA" ? "ip" : "dns"
            findings.append(OsintFinding(
                source: "doh",
                kind: kind,
                value: dataStr,
                relevance: type == "A" ? "signal" : "static",
                note: "\(type) \(name)"
            ))
        }
    }

    private func crtsh(_ domain: String, into findings: inout [OsintFinding]) async {
        let q = "%25.\(domain)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? domain
        guard let url = URL(string: "https://crt.sh/?q=\(q)&output=json") else { return }
        let (code, data) = await OsintHTTP.get(url: url)
        guard code == 200, let arr = OsintHTTP.jsonObject(data) as? [[String: Any]] else { return }
        var seen = Set<String>()
        for row in arr {
            let name = (row["name_value"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
            if name.isEmpty || seen.contains(name) { continue }
            seen.insert(name)
            findings.append(OsintFinding(source: "crt.sh", kind: "cert", value: name, relevance: "signal"))
            if seen.count >= 12 { break }
        }
    }

    private func rdapDomain(_ domain: String, into findings: inout [OsintFinding]) async {
        guard let url = URL(string: "https://rdap.org/domain/\(domain)") else { return }
        let (code, data) = await OsintHTTP.get(url: url)
        guard code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any] else { return }
        if let handle = obj["handle"] as? String {
            findings.append(OsintFinding(source: "rdap", kind: "domain", value: handle, relevance: "static"))
        }
        if let status = obj["status"] as? [String] {
            findings.append(OsintFinding(source: "rdap", kind: "note", value: status.joined(separator: ", "), relevance: "static"))
        }
    }

    private func rdapIP(_ ip: String, into findings: inout [OsintFinding]) async {
        guard let url = URL(string: "https://rdap.org/ip/\(ip)") else { return }
        let (code, data) = await OsintHTTP.get(url: url)
        guard code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any] else { return }
        if let name = obj["name"] as? String {
            findings.append(OsintFinding(source: "rdap", kind: "ip", value: name, relevance: "static"))
        }
        if let country = obj["country"] as? String {
            findings.append(OsintFinding(source: "rdap", kind: "geo", value: country, relevance: "signal"))
        }
    }

    private func internetDB(_ ip: String, into findings: inout [OsintFinding]) async {
        guard let url = URL(string: "https://internetdb.shodan.io/\(ip)") else { return }
        let (code, data) = await OsintHTTP.get(url: url)
        guard code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any] else { return }
        if let ports = obj["ports"] as? [Int] {
            findings.append(OsintFinding(
                source: "internetdb",
                kind: "service",
                value: ports.map(String.init).joined(separator: ", "),
                relevance: ports.isEmpty ? "static" : "signal",
                note: "open ports"
            ))
        }
        if let vulns = obj["vulns"] as? [String] {
            for v in vulns.prefix(8) {
                findings.append(OsintFinding(source: "internetdb", kind: "vuln", value: v, relevance: "signal"))
            }
        }
        if let hostnames = obj["hostnames"] as? [String] {
            for h in hostnames.prefix(6) {
                findings.append(OsintFinding(source: "internetdb", kind: "domain", value: h, relevance: "static"))
            }
        }
    }

    private func shodanHost(_ ip: String, key: String, into findings: inout [OsintFinding]) async {
        guard let url = URL(string: "https://api.shodan.io/shodan/host/\(ip)?key=\(key)") else { return }
        let (code, data) = await OsintHTTP.get(url: url)
        guard code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any] else {
            findings.append(OsintFinding(source: "shodan", kind: "note", value: "Shodan HTTP \(code)", relevance: "static"))
            return
        }
        if let org = obj["org"] as? String {
            findings.append(OsintFinding(source: "shodan", kind: "infra", value: org, relevance: "signal"))
        }
        if let os = obj["os"] as? String {
            findings.append(OsintFinding(source: "shodan", kind: "note", value: "OS \(os)", relevance: "static"))
        }
    }

    // MARK: - Web3

    private func web3(_ q: String, settings: SettingsStore) async -> ([OsintFinding], [OsintAction], [String]) {
        var findings: [OsintFinding] = []
        let actions: [OsintAction] = []
        var brief: [String] = ["Ethereum address — public RPC balance. Etherscan if a key is set."]
        let addr = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://eth.llamarpc.com") else {
            return (findings, actions, brief)
        }
        let (code, data) = await OsintHTTP.postJSON(url: url, body: [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [addr, "latest"],
            "id": 1
        ])
        if code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
           let hexBal = obj["result"] as? String {
            let wei = Int64(hexBal.dropFirst(2), radix: 16) ?? 0
            let eth = Double(wei) / 1e18
            findings.append(OsintFinding(
                source: "eth.rpc",
                kind: "wallet",
                value: String(format: "%.6f ETH", eth),
                relevance: "signal",
                note: addr
            ))
        } else {
            findings.append(OsintFinding(source: "eth.rpc", kind: "note", value: "RPC HTTP \(code)", relevance: "static"))
        }
        if !settings.etherscanApiKey.isEmpty,
           let es = URL(string: "https://api.etherscan.io/api?module=account&action=txlist&address=\(addr)&startblock=0&endblock=99999999&page=1&offset=5&sort=desc&apikey=\(settings.etherscanApiKey)") {
            let (c2, d2) = await OsintHTTP.get(url: es)
            if c2 == 200, let obj = OsintHTTP.jsonObject(d2) as? [String: Any],
               let rows = obj["result"] as? [[String: Any]] {
                findings.append(OsintFinding(source: "etherscan", kind: "note", value: "\(rows.count) recent txs", relevance: "static"))
            }
        }
        findings.append(OsintFinding(
            source: "web3",
            kind: "url",
            value: "Open in explorer",
            relevance: "static",
            url: "https://etherscan.io/address/\(addr)"
        ))
        return (findings, actions, brief)
    }

    private func slug(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
